# Deploying on Proxmox (LXC or VM)

This guide covers running the π RuView / WiFi-DensePose Rust sensing stack
(`docker/docker-compose.prod.yml`) unattended on a Proxmox VE host, either
inside an LXC container or a full VM. It assumes a host with considerable
spare capacity — the defaults below target a dedicated container/VM with
room to run several ESP32 mesh nodes and keep CSI history without starving
other guests on the same hypervisor.

For what's actually being deployed, see [`docker/docker-compose.prod.yml`](../../docker/docker-compose.prod.yml):
`sensing-server` (the CSI signal-processing + UI server) and `nvsim-server`
(the NV-diamond simulator dashboard, ADR-092), with an optional Caddy
reverse-proxy profile.

## LXC vs VM

| | LXC (recommended default) | VM |
|---|---|---|
| Overhead | Shares the Proxmox host kernel — near-native CPU, lower RAM overhead | Full virtualization — a few hundred MB RAM and some CPU held by the guest kernel |
| Docker support | Works via nesting (`features: nesting=1,keyctl=1`); Debian/Ubuntu template | Native, no caveats |
| GPU passthrough | Possible but fiddly (device cgroup passthrough of `/dev/nvidia*`) | Straightforward PCI passthrough |
| Live migration / snapshots | Supported, but unprivileged containers have some restrictions | Full support, independent of host kernel |
| Boot isolation | Shares host kernel — a container kernel panic path is a host-kernel path | Fully isolated kernel |

**Use an LXC container by default.** Nothing in this stack needs a GPU
(`sensing-server` and `nvsim-server` are both CPU-bound — signal processing
and physics simulation, not neural-net inference) or kernel-module access,
so the LXC's lower overhead is pure upside. Reach for a VM only if you
specifically want kernel isolation, plan to pass through a GPU for future
`wifi-densepose-nn`/ONNX work, or want migration/snapshot behavior fully
decoupled from the Proxmox host's kernel.

## Sizing

| Tier | vCPU | RAM | Disk | Fits |
|------|------|-----|------|------|
| Minimum | 2 | 4 GB | 20 GB | Single ESP32 node, evaluation |
| **Considerable resources (default in this guide)** | **8** | **16 GB** | **100 GB** | 4-6 node mesh, weeks of CSI recordings, nvsim-server alongside |
| Large mesh | 16+ | 32 GB+ | 250 GB+ | 6+ nodes, long-term recording retention, headroom for future GPU inference |

`docker/.env.prod.example`'s per-container CPU/memory limits (`SENSING_CPU_LIMIT=4`,
`SENSING_MEM_LIMIT=4g`, etc.) are sized for the "considerable resources" row —
they cap each container so one runaway process can't consume the whole
guest, while leaving headroom for the host OS and Docker itself. Raise them
if you provision a bigger guest.

Disk sizing is driven almost entirely by `sensing-recordings` (the
`data/recordings` volume) if you record CSI sessions for later training —
budget accordingly for your retention window.

## 1. Create the LXC container

Run these on the Proxmox host shell (adjust `CTID`, `--storage`, bridge, and
template names to match your environment — check available templates first
with `pveam available` / `pveam list local`, and storage pools with
`pvesm status`).

```bash
# Download a Debian 12 template if you don't already have one cached
pveam update
pveam download local debian-12-standard_12.7-1_amd64.tar.zst

CTID=200

pct create "$CTID" local:vztmpl/debian-12-standard_12.7-1_amd64.tar.zst \
  --hostname ruview \
  --cores 8 \
  --memory 16384 \
  --swap 2048 \
  --rootfs local-lvm:100 \
  --net0 name=eth0,bridge=vmbr0,ip=dhcp \
  --features nesting=1,keyctl=1 \
  --unprivileged 1 \
  --onboot 1

pct start "$CTID"
```

- `--features nesting=1,keyctl=1` is required for Docker to run inside the
  container.
- `--unprivileged 1` is the safer default and works fine for this stack (no
  privileged device access is needed — ESP32 CSI arrives over ordinary UDP,
  not a passthrough device). Drop to `--unprivileged 0` only if you hit a
  specific capability wall.
- Give the container a static DHCP reservation or a static `ip=` so the
  ESP32 mesh's `--target-ip` (see `firmware/esp32-csi-node/provision.py`)
  stays valid across reboots.

## 2. Install Docker inside the container

```bash
pct exec "$CTID" -- bash -c '
  apt-get update && apt-get install -y ca-certificates curl gnupg git
  install -m 0755 -d /etc/apt/keyrings
  curl -fsSL https://download.docker.com/linux/debian/gpg -o /etc/apt/keyrings/docker.asc
  chmod a+r /etc/apt/keyrings/docker.asc
  echo \
    "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/debian \
    $(. /etc/os-release && echo "$VERSION_CODENAME") stable" \
    | tee /etc/apt/sources.list.d/docker.list > /dev/null
  apt-get update
  apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin
'
```

Verify:

```bash
pct exec "$CTID" -- docker run --rm hello-world
```

## 3. Clone the repo and deploy

```bash
# Use your own fork's URL if you have one; this is the upstream repo.
REPO_URL=https://github.com/ruvnet/RuView.git

pct exec "$CTID" -- bash -c "
  git clone --recurse-submodules '$REPO_URL' /opt/ruview
  cd /opt/ruview
  cp docker/.env.prod.example docker/.env.prod
"
```

Edit `/opt/ruview/docker/.env.prod` inside the container (`pct exec "$CTID"
-- $EDITOR /opt/ruview/docker/.env.prod` or mount the container's rootfs)
to set `CSI_SOURCE=esp32` once your mesh is provisioned and, for a
multi-node mesh, `SENSING_NODE_POSITIONS`.

```bash
pct exec "$CTID" -- bash -c '
  cd /opt/ruview
  docker compose -f docker/docker-compose.prod.yml --env-file docker/.env.prod up -d --build
'
```

Check status and health:

```bash
pct exec "$CTID" -- docker compose -f /opt/ruview/docker/docker-compose.prod.yml ps
pct exec "$CTID" -- curl -fsS http://localhost:3000/health
pct exec "$CTID" -- curl -fsS http://localhost:7878/api/health
```

The UI is at `http://<container-ip>:3000/`, the nvsim dashboard at
`http://<container-ip>:7878/`.

## 4. Network and firewall

Open (or confirm reachable) on the container/VM's Proxmox firewall and any
upstream router/VLAN ACLs:

| Port | Protocol | Purpose |
|------|----------|---------|
| 5005 | UDP | ESP32 CSI ingest — must reach `sensing-server` from the WiFi/VLAN the ESP32 mesh sits on |
| 3000 | TCP | REST API + UI + `/ws/sensing` WebSocket |
| 3001 | TCP | Secondary WebSocket listener (same `/ws/sensing` route; kept for compatibility) |
| 7878 | TCP | nvsim dashboard |
| 80, 443 | TCP | Only if you enable the `proxy` Caddy profile |

`sensing-server` and `nvsim-server` have **no built-in authentication** —
this stack is designed to sit on a trusted LAN/VLAN with the ESP32 mesh, not
be exposed directly to the internet. If you need remote access, put it
behind a VPN (Tailscale/WireGuard) or the optional Caddy `proxy` profile
with your own auth in front, rather than port-forwarding 3000/7878 on your
router.

## 5. Persistent storage and backups

`sensing-models` and `sensing-recordings` are named Docker volumes, which
Proxmox backs up as part of the container's rootfs (`vzdump`/PBS) by
default. For larger recording retention, consider instead bind-mounting a
dedicated Proxmox-managed disk or ZFS dataset into the container and
pointing the compose volumes at host paths, so recordings can be backed up
or expired independently of the container's root filesystem.

- **LXC**: `vzdump <CTID> --mode snapshot` (works cleanly if the underlying
  storage supports snapshots, e.g. ZFS/LVM-thin).
- **VM**: standard Proxmox VM snapshot/backup applies; no container-specific
  caveats.

## 6. Updating

```bash
pct exec "$CTID" -- bash -c '
  cd /opt/ruview
  git pull --recurse-submodules
  docker compose -f docker/docker-compose.prod.yml --env-file docker/.env.prod up -d --build
'
```

This rebuilds only what changed and restarts affected services; named
volumes (models, recordings) persist across the rebuild.

## Deploying on a VM instead

The container-specific steps above (`pct create`, `pct exec`, `--features
nesting=1,keyctl=1`) don't apply — everything from **step 2** onward
(installing Docker, cloning the repo, `docker compose up`) is identical
inside a VM's shell. Create the VM with Debian 12 (or your distro of choice)
sized per the [Sizing](#sizing) table, install Docker per
[step 2](#2-install-docker-inside-the-container), then continue from
[step 3](#3-clone-the-repo-and-deploy).

## See also

- [`scripts/deploy-proxmox-lxc.sh`](../../scripts/deploy-proxmox-lxc.sh) —
  template script automating steps 1-3 above; review and edit the variables
  at the top before running it on your Proxmox host.
- [Build Guide](../build-guide.md) — building from source without Docker.
- [ADR-028](../adr/ADR-028-esp32-capability-audit.md) — ESP32 capability
  audit (context on what the sensing server expects from the mesh).
