# ADR-096: Production Deployment via Docker Compose on Proxmox (LXC)

| Field       | Value      |
|-------------|------------|
| **Status**  | Accepted   |
| **Date**    | 2026-08-08 |
| **Authors** | ruv        |

## Context

`docker/docker-compose.yml` and `docker/Dockerfile.rust` cover quick local
evaluation of `wifi-densepose-sensing-server` (simulated CSI, no persistence
guarantees, root container user, no healthcheck) but nothing production-
hardened. Separately, `docs/build-guide.md`'s "Docker Deployment" section
described a Kubernetes/Docker-Swarm-based Python stack (multi-stage
`Dockerfile` with `development`/`production`/`testing`/`security` targets,
Postgres, Redis, Prometheus, Grafana, Swarm secrets) that never existed for
`v2/` — `wifi-densepose-api` (the crate that stack implies) is an empty stub
crate, and `.github/workflows/cd.yml` deploys to a Kubernetes cluster and a
domain (`wifi-densepose.com`) this project doesn't control. That
documentation was aspirational, not real, and actively misleading for anyone
trying to stand up a production instance.

The concrete need: run `wifi-densepose-sensing-server` (and optionally
`nvsim-server`) unattended, long-term, on a self-hosted machine with
considerable spare capacity — the common case being a home-lab or small-
office Proxmox VE host — reachable by an ESP32 CSI mesh on the local
network.

## Decision

**Docker Compose, not Kubernetes or Swarm**, is the production deployment
mechanism. Neither service is a distributed, multi-replica workload —
`sensing-server` owns in-process CSI stream state per node and isn't
designed to be horizontally scaled behind a load balancer, and the target
environment (a single self-hosted host) has no cluster to orchestrate
against. `docker/docker-compose.prod.yml` (new) hardens the existing
Dockerfiles rather than replacing them:

- **Non-root container user** (`sensing`/`nvsim` in their respective
  Dockerfiles) and a `HEALTHCHECK` against each service's `/health` (or
  `/api/health`) endpoint.
- **Per-service resource limits** (`deploy.resources.limits`/`reservations`,
  tunable via `docker/.env.prod`) so one container can't starve the host or
  its siblings — this works under plain `docker compose up` in Compose v2,
  no Swarm mode required.
- **Named volumes** for `data/models` and `data/recordings`, decoupling
  state from the container filesystem.
- **JSON-file logging with rotation** (`max-size`/`max-file`) instead of
  unbounded default logs.
- **An opt-in `proxy` profile** (Caddy) for a single HTTPS entrypoint,
  off by default because most deployments are LAN-only and Caddy's
  automatic-HTTPS path assumes a public domain.

**Proxmox LXC is the recommended default over a VM.** Neither service needs
GPU access (both are CPU-bound: DSP/signal processing and a physics
simulator, not neural-net inference) or kernel-module/device access, so an
unprivileged LXC container with Docker nesting enabled gets near-native
performance with lower overhead than a VM, at no functional cost. A VM
remains documented as an equally-supported fallback (everything from
"install Docker" onward is identical) for cases needing full kernel
isolation or a future GPU passthrough path for `wifi-densepose-nn`/ONNX
inference. See `docs/deployment/proxmox.md` for the sizing table, LXC-vs-VM
comparison, and step-by-step setup; `scripts/deploy-proxmox-lxc.sh`
templates the `pct create` + Docker install + repo clone steps for the
Proxmox host side.

**No authentication layer was added.** Both services already have none, and
adding one is a larger design decision (who authenticates: the ESP32 nodes
sending UDP CSI frames, or just the HTTP/UI/WebSocket clients?) than this
ADR's scope. Instead, the compose file's header comment and the Proxmox
guide both call out explicitly that these services are LAN/VLAN-only by
design, and recommend a VPN or an authenticating reverse proxy for any
remote access rather than exposing ports directly.

`docs/build-guide.md`'s Docker Deployment section was rewritten to describe
the real `docker/` artifacts instead of the fictional Swarm stack; the stale
claims about a root-level `Dockerfile`/`docker-compose.prod.yml` are gone.

## Consequences

- Deploying now means `docker compose -f docker/docker-compose.prod.yml
  --env-file docker/.env.prod up -d --build` on any Docker host — Proxmox
  LXC/VM, bare metal, or otherwise — not just Proxmox specifically.
- `wifi-densepose-api`, `wifi-densepose-db`, Postgres, and Redis remain
  unused by this deployment path; if/when `wifi-densepose-api` is actually
  implemented with persistent storage needs, it gets its own compose
  service and ADR rather than retrofitting this one.
- No TLS/auth by default is a deliberate LAN-first tradeoff, not an
  oversight — revisit if a public-internet-facing deployment becomes a
  real use case.
- `.github/workflows/cd.yml`'s Kubernetes pipeline is unaffected and remains
  unused/aspirational; reconciling or removing it is out of scope here.

## References

- `docker/docker-compose.prod.yml`, `docker/Dockerfile.rust`,
  `docker/.env.prod.example`, `docker/Caddyfile.example`
- `docs/deployment/proxmox.md`, `scripts/deploy-proxmox-lxc.sh`
- [ADR-028](ADR-028-esp32-capability-audit.md) — what the sensing server
  expects from the ESP32 mesh
- [ADR-092](ADR-092-nvsim-dashboard-implementation.md) — `nvsim-server`,
  the second service in the production stack
