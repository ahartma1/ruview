#!/usr/bin/env bash
# deploy-proxmox-lxc.sh — Provision a Proxmox LXC container running the
# RuView / WiFi-DensePose production Docker Compose stack.
#
# Run this ON THE PROXMOX HOST (needs `pct`, `pveam`, `pvesm`), not inside
# this repo's checkout. It is a TEMPLATE: review and edit the variables
# below (especially STORAGE, BRIDGE, and TEMPLATE) to match your Proxmox
# environment before running — defaults are reasonable guesses, not
# guaranteed to match your storage pool or network bridge names.
#
# What it does:
#   1. Creates an unprivileged Debian 12 LXC container with Docker nesting
#      enabled, sized per the "considerable resources" tier.
#   2. Starts it and installs Docker Engine + Compose plugin inside.
#   3. Clones this repo and copies docker/.env.prod.example to docker/.env.prod.
#   4. Does NOT start the stack — edit docker/.env.prod first (CSI_SOURCE,
#      SENSING_NODE_POSITIONS), then run the printed `docker compose up`
#      command yourself.
#
# See docs/deployment/proxmox.md for the full walkthrough and rationale.
#
# Usage: edit the variables below, then run as root on the Proxmox host:
#   bash deploy-proxmox-lxc.sh

set -euo pipefail

# ─── Variables — edit these ────────────────────────────────────────────────
CTID="${CTID:-200}"                      # Container ID; must not already exist
HOSTNAME="${HOSTNAME:-ruview}"
CORES="${CORES:-8}"                      # "Considerable resources" tier — see docs/deployment/proxmox.md
MEMORY_MB="${MEMORY_MB:-16384}"
SWAP_MB="${SWAP_MB:-2048}"
DISK_GB="${DISK_GB:-100}"
STORAGE="${STORAGE:-local-lvm}"          # Check: pvesm status
BRIDGE="${BRIDGE:-vmbr0}"                # Check: ip link, or Datacenter > Network in the web UI
NET_IP="${NET_IP:-dhcp}"                 # Or e.g. 192.168.1.50/24,gw=192.168.1.1
TEMPLATE_STORAGE="${TEMPLATE_STORAGE:-local}"
TEMPLATE="${TEMPLATE:-debian-12-standard_12.7-1_amd64.tar.zst}"
REPO_URL="${REPO_URL:-https://github.com/ruvnet/RuView.git}"
INSTALL_DIR="${INSTALL_DIR:-/opt/ruview}"
# ────────────────────────────────────────────────────────────────────────────

if pct status "$CTID" &>/dev/null; then
    echo "Error: container $CTID already exists (pct status $CTID). Pick a different CTID or remove it first." >&2
    exit 1
fi

echo "==> Ensuring template ${TEMPLATE_STORAGE}:vztmpl/${TEMPLATE} is available"
pveam update
if ! pveam list "$TEMPLATE_STORAGE" | grep -q "$TEMPLATE"; then
    pveam download "$TEMPLATE_STORAGE" "$TEMPLATE"
fi

echo "==> Creating container $CTID ($HOSTNAME): ${CORES} vCPU, ${MEMORY_MB}MB RAM, ${DISK_GB}GB disk"
pct create "$CTID" "${TEMPLATE_STORAGE}:vztmpl/${TEMPLATE}" \
    --hostname "$HOSTNAME" \
    --cores "$CORES" \
    --memory "$MEMORY_MB" \
    --swap "$SWAP_MB" \
    --rootfs "${STORAGE}:${DISK_GB}" \
    --net0 "name=eth0,bridge=${BRIDGE},ip=${NET_IP}" \
    --features nesting=1,keyctl=1 \
    --unprivileged 1 \
    --onboot 1

echo "==> Starting container"
pct start "$CTID"

echo "==> Waiting for network"
for _ in $(seq 1 30); do
    if pct exec "$CTID" -- getent hosts download.docker.com &>/dev/null; then
        break
    fi
    sleep 2
done

echo "==> Installing Docker inside the container"
pct exec "$CTID" -- bash -c '
    set -euo pipefail
    apt-get update
    apt-get install -y ca-certificates curl gnupg git
    install -m 0755 -d /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/debian/gpg -o /etc/apt/keyrings/docker.asc
    chmod a+r /etc/apt/keyrings/docker.asc
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/debian $(. /etc/os-release && echo "$VERSION_CODENAME") stable" \
        > /etc/apt/sources.list.d/docker.list
    apt-get update
    apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin
'

echo "==> Cloning $REPO_URL into ${INSTALL_DIR}"
pct exec "$CTID" -- bash -c "
    set -euo pipefail
    git clone --recurse-submodules '${REPO_URL}' '${INSTALL_DIR}'
    cp '${INSTALL_DIR}/docker/.env.prod.example' '${INSTALL_DIR}/docker/.env.prod'
"

CONTAINER_IP="$(pct exec "$CTID" -- hostname -I | awk '{print $1}')"

cat <<EOF

==> Done. Container $CTID ($HOSTNAME) is up at ${CONTAINER_IP:-<check pct exec $CTID -- ip a>}.

Next steps:
  1. Edit ${INSTALL_DIR}/docker/.env.prod inside the container
     (set CSI_SOURCE=esp32 and SENSING_NODE_POSITIONS once your mesh is provisioned):
       pct exec $CTID -- \$EDITOR ${INSTALL_DIR}/docker/.env.prod

  2. Start the stack:
       pct exec $CTID -- bash -c "cd ${INSTALL_DIR} && docker compose -f docker/docker-compose.prod.yml --env-file docker/.env.prod up -d --build"

  3. Verify:
       curl -fsS http://${CONTAINER_IP:-<container-ip>}:3000/health

See docs/deployment/proxmox.md for network/firewall requirements (UDP 5005
for the ESP32 mesh) and backup guidance.
EOF
