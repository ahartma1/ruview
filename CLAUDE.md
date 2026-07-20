# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project overview

**π RuView** (package/crate name `wifi-densepose`) turns commodity WiFi Channel State
Information (CSI) into spatial sensing: presence/occupancy, breathing/heart rate, activity
recognition, room fingerprinting, and 17-keypoint pose estimation — no cameras, no wearables.
Sensors are cheap ESP32-S3 boards (~$9); processing runs on an edge Rust pipeline, optionally
backed by a [Cognitum Seed](https://cognitum.one) for persistent memory and cryptographic
attestation.

The repo has two codebases:
- **`v2/`** — the active Rust workspace (20 crates). This is where almost all new work happens.
- **`archive/v1/`** — the original Python implementation (FastAPI + PyTorch). Kept for the
  deterministic proof pipeline (`archive/v1/data/proof/`) and historical reference; not the
  target for new features.

Root-level `wifi_densepose/` is just an empty Python package stub; `pyproject.toml` describes
the archived v1 package. Don't confuse it with `v2/`.

## Commands

### Rust workspace (`v2/`) — primary development surface

```bash
cd v2
cargo build --release                              # build (LTO + -O3 release profile)
cargo test --workspace --no-default-features        # full suite — this is the CI command, use it
cargo test --workspace --no-default-features -- --nocapture

# Single crate / single test
cargo check -p wifi-densepose-train --no-default-features
cargo test -p wifi-densepose-signal --no-default-features
cargo test -p wifi-densepose-signal --no-default-features test_phase_unwrap -- --exact

cargo clippy --workspace --no-default-features
cargo fmt --all

cargo bench --package wifi-densepose-signal          # signal-processing benchmarks
```

`--no-default-features` matters: several crates default-enable GPU/ONNX/tch backends that
require system libtorch/OpenBLAS and aren't needed to compile-check most changes. CI
(`.github/workflows/ci.yml`) always runs with it.

`crates/wifi-densepose-wasm-edge` is **excluded** from the workspace (`v2/Cargo.toml`
`[workspace] exclude`) because it's `no_std` and targets `wasm32-unknown-unknown` — building it
breaks `cargo test --workspace` otherwise. Build it separately:
```bash
cargo build -p wifi-densepose-wasm-edge --target wasm32-unknown-unknown --release
```
`crates/ruv-neural` is its own **nested** Cargo workspace (12 sub-crates), not a member of the
top-level `v2` workspace — `cd` into it before running cargo commands there.

### Python (archived v1 + deterministic proof)

```bash
# Deterministic CSI proof — the "Trust Kill Switch": replays a fixed reference signal
# through the production pipeline and checks the output hash against a published value
python archive/v1/data/proof/verify.py          # must print VERDICT: PASS
./verify                                          # same thing, wrapper script; ./verify --verbose --audit for more

cd archive/v1 && python -m pytest tests/ -x -q
cd archive/v1 && python -m pytest tests/unit/test_foo.py::test_bar -x   # single test
```

If the proof hash changes (e.g. after a numpy/scipy bump), regenerate it deliberately, don't
just delete the check:
```bash
python archive/v1/data/proof/verify.py --generate-hash
python archive/v1/data/proof/verify.py
```

### Makefile

`make help` lists targets, but **`build-rust`, `build-wasm`, `test-rust`, `bench` are stale** —
they `cd rust-port/wifi-densepose-rs`, a path that no longer exists (the crate moved to `v2/`).
Use the `cargo` commands above directly instead of those Makefile targets. `make verify`,
`make install*`, `make run-api`, `make run-viz` are current and work as documented.

### ESP32 firmware (Windows — Python subprocess required for ESP-IDF)

```bash
# Must strip MSYSTEM env vars for ESP-IDF v5.4 under Git Bash before invoking idf.py
# 8MB build: default sdkconfig.defaults
# 4MB build: cp sdkconfig.defaults.4mb sdkconfig.defaults, then same idf.py build/flash

python firmware/esp32-csi-node/provision.py --port COM7 \
  --ssid "YourWiFi" --password "secret" --target-ip 192.168.1.20
python -m serial.tools.miniterm COM7 115200      # serial monitor
```
Always validate firmware changes against **real WiFi CSI on hardware**, not mock mode — a past
regression (Kconfig threshold bug) only reproduced with real CSI.

**Firmware release process:** build 8MB (from `sdkconfig.defaults.template`) and 4MB (from
`sdkconfig.defaults.4mb`) images, no mock; save the 6 binaries (`esp32-csi-node.bin`,
`bootloader.bin`, `partition-table.bin`, `ota_data_initial.bin`, `esp32-csi-node-4mb.bin`,
`partition-table-4mb.bin`); tag `vX.Y.Z-esp32` and push; `gh release create` with the binaries;
verify on real hardware before publishing.

### Witness bundle (ADR-028) — full validation + attestation

Run this after any significant change, not just before a release:
```bash
cd v2 && cargo test --workspace --no-default-features   # 1) Rust tests
python archive/v1/data/proof/verify.py                  # 2) Python proof — VERDICT: PASS
bash scripts/generate-witness-bundle.sh                  # 3) bundle: tests + proof + firmware hashes
cd dist/witness-bundle-ADR028-*/ && bash VERIFY.sh        # 4) self-verify — must be 7/7 PASS
```
The bundle (`dist/witness-bundle-ADR028-<sha>.tar.gz`) packages `WITNESS-LOG-028.md` (attestation
matrix), the ADR-028 audit, the proof script + hash, the full cargo test log, ESP32 firmware
source hashes, and a crate version manifest — see `docs/adr/ADR-028-esp32-capability-audit.md`.

## Architecture

### Signal pipeline (why the crates are structured this way)

```
ESP32 mesh (4-6 nodes, ch 1/6/11) --TDM protocol--> CSI frames
  --> Multi-band fusion (3 channels x 56 subcarriers = 168 virtual subcarriers/link)
  --> Multistatic fusion (N x (N-1) links -> attention-weighted cross-viewpoint embedding)
  --> Coherence gate (accept / predict-only / reject / recalibrate)
  --> Signal processing (Hampel filter, SpotFi, Fresnel zone, BVP, spectrogram)
  --> RuVector backbone (attention, graph algorithms, compression, field model)
  --> Neural network inference -> 17 keypoints + vital signs + room model
```
This is why `wifi-densepose-signal`, `wifi-densepose-ruvector`, and `wifi-densepose-nn` are
separate crates: signal processing is backend-agnostic DSP, ruvector is the shared AI/attention
substrate (vendored from the `ruvector` git submodule), and `nn` is only inference-time model
execution (ONNX/tch/candle backends selected via feature flags).

### Rust workspace crates (`v2/crates/`)

| Crate | Role |
|-------|------|
| `wifi-densepose-core` | Core types, traits, error types, CSI frame primitives |
| `wifi-densepose-signal` | Signal processing (FFT, phase unwrap, Doppler, correlation) + RuvSense multistatic sensing |
| `wifi-densepose-nn` | Neural network inference (ONNX Runtime, tch/libtorch, candle backends) |
| `wifi-densepose-train` | Training pipeline (depends on `signal`, `nn`; ruvector + ruview_metrics integration) |
| `wifi-densepose-mat` | Mass Casualty Assessment Tool — WiFi-based disaster survivor detection |
| `wifi-densepose-hardware` | Device adapters: ESP32, Intel 5300, Atheros AR9580, UDP, PCAP; TDM + secure-TDM + QUIC transport |
| `wifi-densepose-ruvector` | RuVector v2.0.4 integration + cross-viewpoint fusion (`viewpoint/`) |
| `wifi-densepose-api` | REST/WebSocket API (Axum) |
| `wifi-densepose-db` | Database layer (Postgres, SQLite, Redis via SQLx) |
| `wifi-densepose-config` | Configuration loading (env, YAML, TOML) |
| `wifi-densepose-wasm` | Browser WASM bindings (depends on `mat`) |
| `wifi-densepose-wasm-edge` | 67 WASM sensing modules for on-ESP32 execution (ADR-040/041); **excluded** from workspace, builds for `wasm32-unknown-unknown` only |
| `wifi-densepose-cli` | `wifi-densepose` CLI binary (depends on `mat`) |
| `wifi-densepose-sensing-server` | Lightweight Axum server for the WiFi sensing UI (depends on `wifiscan`) |
| `wifi-densepose-wifiscan` | Multi-BSSID WiFi scanning (ADR-022) |
| `wifi-densepose-vitals` | ESP32 CSI-grade heart/respiratory rate extraction (ADR-021) |
| `wifi-densepose-desktop` | Tauri v2 + React/TS desktop app for managing ESP32 sensing networks (WIP) |
| `wifi-densepose-pointcloud` | Real-time dense point cloud from camera depth + WiFi CSI tomography |
| `wifi-densepose-geo` | Geospatial integration — free satellite tiles, DEM, OSM, temporal tracking |
| `nvsim` | Deterministic NV-diamond magnetometer pipeline simulator (ADR-089), standalone leaf, WASM-ready |
| `nvsim-server` | Axum REST + WebSocket server fronting `nvsim` (ADR-092) |
| `ruv-neural` (nested workspace, not a `v2` member) | Separate neuromorphic/graph-memory sub-project — 12 sub-crates under `v2/crates/ruv-neural/` |

### RuvSense multistatic sensing (`v2/crates/wifi-densepose-signal/src/ruvsense/`)

15 modules implementing the multistatic pipeline stages above:
`multiband.rs` (CSI fusion), `phase_align.rs` (LO phase offset), `multistatic.rs`
(attention-weighted fusion), `coherence.rs` / `coherence_gate.rs` (drift-aware accept/reject),
`pose_tracker.rs` (17-keypoint Kalman tracker + AETHER re-ID), `field_model.rs` (SVD room
eigenstructure), `tomography.rs` (RF tomography, ISTA L1), `longitudinal.rs` (Welford stats,
drift detection), `intention.rs` (200-500ms pre-movement lead signals), `cross_room.rs`
(environment fingerprinting), `gesture.rs` / `temporal_gesture.rs` (DTW gesture classification),
`adversarial.rs` (physically-impossible-signal detection), `attractor_drift.rs`.

### Cross-viewpoint fusion (`v2/crates/wifi-densepose-ruvector/src/viewpoint/`)

`attention.rs` (CrossViewpointAttention + geometric bias softmax), `geometry.rs`
(GeometricDiversityIndex, Cramer-Rao bounds), `coherence.rs` (phasor coherence + hysteresis
gate), `fusion.rs` (`MultistaticArray` aggregate root, domain events).

### RuVector integration (ADR-016 complete, ADR-017 signal/MAT integration)

`ruvector-mincut` -> `metrics.rs` (person matching) + `subcarrier_selection.rs`;
`ruvector-attn-mincut` -> `model.rs` (antenna attention) + `spectrogram.rs`;
`ruvector-temporal-tensor` -> `dataset.rs` (compressed CSI buffer) + `breathing.rs`;
`ruvector-solver` -> `subcarrier.rs` (114->56 sparse interpolation) + `triangulation.rs`;
`ruvector-attention` -> `model.rs` (spatial attention) + `bvp.rs`.
`ruvector` is vendored as a git submodule (`vendor/ruvector`), alongside `vendor/midstream` and
`vendor/sublinear-time-solver` (see `.gitmodules`).

### Architecture Decision Records

44 ADRs in `docs/adr/` (`docs/adr/README.md` is the categorized index — hardware/firmware,
signal processing, ML/training, platform/UI, infra). Read the index before making an
architectural change; ADRs are the source of truth for *why*, and DDD models in `docs/ddd/`
define the shared vocabulary (bounded contexts, aggregates) that ADRs reference. Notable
recent/active ones: ADR-040/041 (WASM edge sensing, 67 modules), ADR-059 (live ESP32 CSI
pipeline), ADR-079 (camera-supervised training, 92.9% PCK@20), ADR-082 (pose tracker confirmed-
track filter), ADR-089/090/092 (nvsim NV-diamond simulator), ADR-094 (point-cloud GitHub Pages
deployment).

### Supported hardware

| Device | Chip | Role | Cost |
|--------|------|------|------|
| ESP32-S3 (8MB flash) | Xtensa dual-core | WiFi CSI sensing node | ~$9 |
| ESP32-S3 SuperMini (4MB) | Xtensa dual-core | WiFi CSI (compact) | ~$6 |
| ESP32-C6 + Seeed MR60BHA2 | RISC-V + 60GHz FMCW | mmWave HR/BR/presence | ~$15 |
| HLK-LD2410 | 24GHz FMCW | Presence + distance | ~$3 |

**Not supported:** original ESP32, ESP32-C3 — single-core, can't run the CSI DSP pipeline.

## Key conventions

- **DDD + bounded contexts.** New sensing modes get their own module/crate boundary (see how
  RuvSense and cross-viewpoint fusion are split out from core signal processing); consult
  `docs/ddd/` before introducing a new aggregate.
- **Files under ~500 lines**; prefer splitting a module over growing one file.
- **TDD, London School (mock-first)** for new Rust/Python code.
- **Event sourcing** for state changes in the sensing/tracking pipeline.
- **Never save working files, scratch docs, or tests to the repo root** — use `v2/crates/*`,
  `archive/v1/`, `docs/adr/`, `docs/ddd/`, or `scripts/`.
- **Crate publishing order** (dependency-ordered; run before `cargo publish` on any of these):
  `core` -> `vitals`/`wifiscan`/`hardware`/`config`/`db` (no internal deps) -> `signal` (deps on
  `core`) -> `nn`/`ruvector` (workspace-only) -> `train` (deps on `signal`, `nn`) -> `mat` (deps
  on `core`, `signal`, `nn`) -> `api` -> `wasm` (deps on `mat`) -> `sensing-server` (deps on
  `wifiscan`) -> `cli` (deps on `mat`). Newer crates (`geo`, `pointcloud`, `desktop`, `nvsim`,
  `nvsim-server`) aren't yet in this published set — check their `Cargo.toml` deps before adding
  them to the chain.

## Pre-merge checklist

1. `cd v2 && cargo test --workspace --no-default-features` passes (see the README test-count
   badge for the current expected number).
2. `python archive/v1/data/proof/verify.py` prints `VERDICT: PASS`.
3. Update `README.md` (platform tables, crate descriptions, hardware tables) if scope changed.
4. Update this file's crate/ADR/module tables if scope changed.
5. Add a `CHANGELOG.md` entry under `[Unreleased]`.
6. Update `docs/user-guide.md` if new data sources, CLI flags, or setup steps were added.
7. Update the ADR index (`docs/adr/README.md`) count/table if a new ADR was created.
8. Regenerate the witness bundle (`bash scripts/generate-witness-bundle.sh`) if tests or the
   proof hash changed.
9. Rebuild the Docker Hub image only if the Dockerfile, deps, or runtime behavior changed.
10. Only republish a crate to crates.io if its public API actually changed.
11. Add any new build artifacts/binaries to `.gitignore`.
12. Run a security review for changes touching hardware/network boundaries
    (`docs/security-audit-wasm-edge-vendor.md` is a precedent for that kind of review).

## Claude-flow / agent tooling

This repo has claude-flow wired in as an MCP server (`.mcp.json`, `autoStart: false`) with
state under `.claude-flow/` and `.claude/` (agents, skills, memory — both committed for team
sharing). It's optional multi-agent orchestration tooling, not something the RuView runtime
depends on. If you use it: batch related agent spawns, file ops, and bash calls into a single
message rather than issuing them one at a time, and prefer the Task tool for actual execution
over calling claude-flow CLI subcommands directly.
