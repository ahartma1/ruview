# Architecture Decision Records

This folder contains 92 Architecture Decision Records (ADRs), numbered ADR-001 through ADR-095 with a few
gaps (ADR-051, ADR-087, ADR-088 are referenced from other ADRs as prospective/planned work but have not
been written yet), plus one companion appendix (`ADR-052-appendix-ddd-bounded-contexts.md`, the DDD bounded-
context model for ADR-052). Together they document every significant technical choice in the RuView /
WiFi-DensePose project.

## Why ADRs?

Building a system that turns WiFi signals into human pose estimation involves hundreds of non-obvious decisions: which signal processing algorithms to use, how to bridge ESP32 firmware to a Rust pipeline, whether to run inference on-device or on a server, how to handle multi-person separation with limited subcarriers.

ADRs capture the **context**, **options considered**, **decision made**, and **consequences** for each of these choices. They serve three purposes:

1. **Institutional memory** — Six months from now, anyone (human or AI) can read *why* we chose IIR bandpass filters over FIR for vital sign extraction, not just see the code.

2. **AI-assisted development** — When an AI agent works on this codebase, ADRs give it the constraints and rationale it needs to make changes that align with the existing architecture. Without them, AI-generated code tends to drift — reinventing patterns that already exist, contradicting earlier decisions, or optimizing for the wrong tradeoffs.

3. **Review checkpoints** — Each ADR is a reviewable artifact. When a proposed change touches the architecture, the ADR forces the author to articulate tradeoffs *before* writing code, not after.

### ADRs and Domain-Driven Design

The project uses [Domain-Driven Design](../ddd/) (DDD) to organize code into bounded contexts — each with its own language, types, and responsibilities. ADRs and DDD work together:

- **ADRs define boundaries**: ADR-029 (RuvSense) established multistatic sensing as a separate bounded context from single-node CSI. ADR-042 (CHCI) defined a new aggregate root for coherent channel imaging.
- **DDD models define the language**: The [RuvSense domain model](../ddd/ruvsense-domain-model.md) defines terms like "coherence gate", "dwell time", and "TDM slot" that ADRs reference precisely.
- **Together they prevent drift**: An AI agent reading ADR-039 knows that edge processing tiers are configured via NVS keys, not compile-time flags — because the ADR says so. The DDD model tells it which aggregate owns that configuration.

### How ADRs are structured

Each ADR follows a consistent format:

- **Context** — What problem or gap prompted this decision
- **Decision** — What we chose to do and how
- **Consequences** — What improved, what got harder, and what risks remain
- **References** — Related ADRs, papers, and code paths

Statuses: **Proposed** (under discussion), **Accepted** (approved and/or implemented), **Superseded** (replaced by a later ADR).

---

## ADR Index

### Hardware and firmware

| ADR | Title | Status |
|-----|-------|--------|
| [ADR-012](ADR-012-esp32-csi-sensor-mesh.md) | ESP32 CSI Sensor Mesh for Distributed Sensing | Accepted (partial) |
| [ADR-018](ADR-018-esp32-dev-implementation.md) | ESP32 Development Implementation Path | Proposed |
| [ADR-028](ADR-028-esp32-capability-audit.md) | ESP32 Capability Audit and Witness Record | Accepted |
| [ADR-029](ADR-029-ruvsense-multistatic-sensing-mode.md) | RuvSense Multistatic Sensing Mode (TDM, channel hopping) | Proposed |
| [ADR-032](ADR-032-multistatic-mesh-security-hardening.md) | Multistatic Mesh Security Hardening | Accepted |
| [ADR-039](ADR-039-esp32-edge-intelligence.md) | ESP32-S3 Edge Intelligence Pipeline (on-device vitals) | Accepted (hardware-validated) |
| [ADR-040](ADR-040-wasm-programmable-sensing.md) | WASM Programmable Sensing (Tier 3) | Accepted |
| [ADR-041](ADR-041-wasm-module-collection.md) | WASM Module Collection (65 edge modules) | Accepted (hardware-validated) |
| [ADR-045](ADR-045-amoled-display-support.md) | AMOLED Display Support (ESP32-S3 CSI Node) | Proposed |
| [ADR-050](ADR-050-provisioning-tool-enhancements.md) | Provisioning Tool Enhancements | Proposed |
| [ADR-057](ADR-057-firmware-csi-build-guard.md) | Firmware CSI Build Guard and sdkconfig.defaults | Accepted |
| [ADR-059](ADR-059-live-esp32-csi-pipeline.md) | Live ESP32 CSI Pipeline Integration | Accepted |
| [ADR-060](ADR-060-provision-channel-mac-filter.md) | Provision Channel Override and MAC Address Filtering | Accepted |
| [ADR-061](ADR-061-qemu-esp32s3-firmware-testing.md) | QEMU ESP32-S3 Emulation for Firmware Testing | Accepted |
| [ADR-062](ADR-062-qemu-swarm-configurator.md) | QEMU ESP32-S3 Swarm Configurator | Accepted |
| [ADR-066](ADR-066-esp32-swarm-seed-coordinator.md) | ESP32 CSI Swarm with Cognitum Seed Coordinator | Proposed |
| [ADR-069](ADR-069-cognitum-seed-csi-pipeline.md) | ESP32 CSI to Cognitum Seed RVF Ingest Pipeline | Accepted |
| [ADR-081](ADR-081-adaptive-csi-mesh-firmware-kernel.md) | Adaptive CSI Mesh Firmware Kernel | Accepted (partial — Phase 3.5 polish pending) |
| [ADR-086](ADR-086-edge-novelty-gate.md) | Edge Novelty Gate (RaBitQ Sensor on Sensor MCU) | Proposed |

### Signal processing and sensing

| ADR | Title | Status |
|-----|-------|--------|
| [ADR-013](ADR-013-feature-level-sensing-commodity-gear.md) | Feature-Level Sensing on Commodity Gear | Accepted |
| [ADR-014](ADR-014-sota-signal-processing.md) | SOTA Signal Processing Algorithms | Accepted |
| [ADR-021](ADR-021-vital-sign-detection-rvdna-pipeline.md) | Vital Sign Detection (breathing, heart rate) | Partial |
| [ADR-030](ADR-030-ruvsense-persistent-field-model.md) | Persistent Field Model and Drift Detection | Proposed |
| [ADR-033](ADR-033-crv-signal-line-sensing-integration.md) | CRV Signal Line Sensing Integration | Proposed |
| [ADR-037](ADR-037-multi-person-pose-detection.md) | Multi-Person Pose Detection from Single ESP32 | Proposed |
| [ADR-042](ADR-042-coherent-human-channel-imaging.md) | Coherent Human Channel Imaging (beyond CSI) | Proposed |
| [ADR-063](ADR-063-mmwave-sensor-fusion.md) | 60GHz mmWave Sensor Fusion with WiFi CSI | Proposed |
| [ADR-064](ADR-064-multimodal-ambient-intelligence.md) | Multimodal Ambient Intelligence (CSI + mmWave + Env Sensors) | Proposed |
| [ADR-068](ADR-068-per-node-state-pipeline.md) | Per-Node State Pipeline for Multi-Node Sensing | Accepted |
| [ADR-073](ADR-073-multifrequency-mesh-scan.md) | Multi-Frequency Mesh Scanning | Proposed |
| [ADR-075](ADR-075-mincut-person-separation.md) | Min-Cut Based Person Separation from Subcarrier Correlation | Proposed |
| [ADR-077](ADR-077-novel-rf-sensing-applications.md) | Novel RF Sensing Applications | Accepted |
| [ADR-078](ADR-078-multifreq-mesh-applications.md) | Multi-Frequency Mesh Sensing Applications | Proposed |
| [ADR-082](ADR-082-pose-tracker-confirmed-output-filter.md) | Pose Tracker Confirmed-Track Output Filter | Accepted |

### Machine learning and training

| ADR | Title | Status |
|-----|-------|--------|
| [ADR-005](ADR-005-sona-self-learning-pose-estimation.md) | SONA Self-Learning for Pose Estimation | Partial |
| [ADR-006](ADR-006-gnn-enhanced-csi-pattern-recognition.md) | GNN-Enhanced CSI Pattern Recognition | Partial |
| [ADR-015](ADR-015-public-dataset-training-strategy.md) | Public Dataset Strategy (MM-Fi, Wi-Pose) | Accepted |
| [ADR-016](ADR-016-ruvector-integration.md) | RuVector Training Pipeline Integration | Accepted |
| [ADR-017](ADR-017-ruvector-signal-mat-integration.md) | RuVector Signal + MAT Integration | Proposed |
| [ADR-020](ADR-020-rust-ruvector-ai-model-migration.md) | Migrate AI Inference to Rust (ONNX Runtime) | Accepted |
| [ADR-023](ADR-023-trained-densepose-model-ruvector-pipeline.md) | Trained DensePose Model with RuVector Pipeline | Proposed |
| [ADR-024](ADR-024-contrastive-csi-embedding-model.md) | Project AETHER: Contrastive CSI Embeddings | Required |
| [ADR-027](ADR-027-cross-environment-domain-generalization.md) | Project MERIDIAN: Cross-Environment Generalization | Proposed |
| [ADR-048](ADR-048-adaptive-csi-classifier.md) | Adaptive CSI Activity Classifier | Accepted |
| [ADR-065](ADR-065-happiness-scoring-seed-bridge.md) | Hotel Guest Happiness Scoring (CSI + Cognitum Seed Bridge) | Proposed |
| [ADR-067](ADR-067-ruvector-v2.0.5-upgrade.md) | RuVector v2.0.4 to v2.0.5 Upgrade + New Crate Adoption | Proposed |
| [ADR-070](ADR-070-self-supervised-pretraining.md) | Self-Supervised Pretraining from Live ESP32 CSI + Cognitum Seed | Accepted |
| [ADR-071](ADR-071-ruvllm-training-pipeline.md) | ruvllm Training Pipeline for CSI Sensing Models | Proposed |
| [ADR-072](ADR-072-wiflow-architecture.md) | WiFlow Pose Estimation Architecture | Proposed |
| [ADR-074](ADR-074-spiking-neural-csi-sensing.md) | Spiking Neural Network for CSI Sensing | Proposed |
| [ADR-076](ADR-076-csi-spectrogram-embeddings.md) | CSI Spectrogram Embeddings (CNN + Graph Transformer) | Proposed |
| [ADR-079](ADR-079-camera-ground-truth-training.md) | Camera Ground-Truth Training Pipeline (92.9% PCK@20) | Accepted |
| [ADR-084](ADR-084-rabitq-similarity-sensor.md) | RaBitQ Similarity Sensor (CSI / Pose / Memory Routing) | Accepted |
| [ADR-085](ADR-085-rabitq-pipeline-expansion.md) | RaBitQ Similarity Sensor — Pipeline Expansion | Proposed |

### Platform and UI

| ADR | Title | Status |
|-----|-------|--------|
| [ADR-019](ADR-019-sensing-only-ui-mode.md) | Sensing-Only UI with Gaussian Splats | Accepted |
| [ADR-022](ADR-022-windows-wifi-enhanced-fidelity-ruvector.md) | Windows WiFi Enhanced Fidelity (multi-BSSID) | Partial |
| [ADR-025](ADR-025-macos-corewlan-wifi-sensing.md) | macOS CoreWLAN WiFi Sensing | Proposed |
| [ADR-031](ADR-031-ruview-sensing-first-rf-mode.md) | RuView Sensing-First RF Mode | Proposed |
| [ADR-034](ADR-034-expo-mobile-app.md) | Expo React Native Mobile App | Accepted |
| [ADR-035](ADR-035-live-sensing-ui-accuracy.md) | Live Sensing UI Accuracy and Data Transparency | Accepted |
| [ADR-036](ADR-036-rvf-training-pipeline-ui.md) | Training Pipeline UI Integration | Proposed |
| [ADR-043](ADR-043-sensing-server-ui-api-completion.md) | Sensing Server UI API Completion (14 endpoints) | Accepted |
| [ADR-044](ADR-044-geospatial-satellite-integration.md) | Geospatial Satellite Integration | Accepted |
| [ADR-047](ADR-047-psychohistory-observatory-visualization.md) | RuView Observatory — Immersive Three.js Visualization | Accepted (implemented) |
| [ADR-049](ADR-049-cross-platform-wifi-interface-detection.md) | Cross-Platform WiFi Interface Detection and Graceful Degradation | Proposed |
| [ADR-052](ADR-052-tauri-desktop-frontend.md) | Tauri Desktop Frontend — Hardware Management & Visualization | Proposed |
| [ADR-053](ADR-053-ui-design-system.md) | UI Design System (Dark Professional + Unity-Inspired) | Accepted |
| [ADR-054](ADR-054-desktop-full-implementation.md) | RuView Desktop Full Implementation | Accepted (in progress) |
| [ADR-055](ADR-055-integrated-sensing-server.md) | Integrated Sensing Server in Desktop App | Accepted |
| [ADR-056](ADR-056-ruview-desktop-capabilities.md) | RuView Desktop Complete Capabilities Reference | Accepted |
| [ADR-058](ADR-058-ruvector-wasm-browser-pose-example.md) | Dual-Modal WASM Browser Pose (Video + WiFi CSI Fusion) | Proposed |
| [ADR-092](ADR-092-nvsim-dashboard-implementation.md) | nvsim Dashboard (Vite + WASM/REST/WS) | Accepted (implemented) |
| [ADR-093](ADR-093-dashboard-gap-analysis.md) | nvsim Dashboard Gap Analysis | Accepted (implemented) |
| [ADR-094](ADR-094-pointcloud-github-pages-deployment.md) | Live 3D Point Cloud Viewer — GitHub Pages Deployment | Proposed |

### Architecture and infrastructure

| ADR | Title | Status |
|-----|-------|--------|
| [ADR-001](ADR-001-wifi-mat-disaster-detection.md) | WiFi-Mat Disaster Detection Architecture | Accepted |
| [ADR-002](ADR-002-ruvector-rvf-integration-strategy.md) | RuVector RVF Integration Strategy | Superseded |
| [ADR-003](ADR-003-rvf-cognitive-containers-csi.md) | RVF Cognitive Containers for CSI | Proposed |
| [ADR-004](ADR-004-hnsw-vector-search-fingerprinting.md) | HNSW Vector Search for Fingerprinting | Partial |
| [ADR-007](ADR-007-post-quantum-cryptography-secure-sensing.md) | Post-Quantum Cryptography for Sensing | Proposed |
| [ADR-008](ADR-008-distributed-consensus-multi-ap.md) | Distributed Consensus for Multi-AP | Proposed |
| [ADR-009](ADR-009-rvf-wasm-runtime-edge-deployment.md) | RVF WASM Runtime for Edge Deployment | Proposed |
| [ADR-010](ADR-010-witness-chains-audit-trail-integrity.md) | Witness Chains for Audit Trail Integrity | Proposed |
| [ADR-011](ADR-011-python-proof-of-reality-mock-elimination.md) | Proof-of-Reality and Mock Elimination | Proposed |
| [ADR-026](ADR-026-survivor-track-lifecycle.md) | Survivor Track Lifecycle (MAT crate) | Accepted |
| [ADR-038](ADR-038-sublinear-goal-oriented-action-planning.md) | Sublinear GOAP for Roadmap Optimization | Proposed |
| [ADR-046](ADR-046-android-tv-box-armbian-deployment.md) | Android TV Box / Armbian Deployment Target | Proposed |
| [ADR-080](ADR-080-qe-remediation-plan.md) | QE Analysis Remediation Plan | Proposed |
| [ADR-083](ADR-083-per-cluster-pi-compute-hop.md) | Per-Cluster Pi Compute Hop | Proposed |
| [ADR-089](ADR-089-nvsim-nv-diamond-simulator.md) | nvsim — NV-Diamond Magnetometer Pipeline Simulator | Accepted |
| [ADR-090](ADR-090-nvsim-lindblad-extension.md) | nvsim — Lindblad/Hamiltonian Solver Extension | Proposed (conditional) |
| [ADR-091](ADR-091-stand-off-radar-tier-research.md) | Stand-off Radar Tier Research (77GHz / sub-THz) | Proposed (research only) |
| [ADR-095](ADR-095-quality-engineering-security-hardening.md) | Quality Engineering Response — Security Hardening & Code Quality | Accepted |

---

## Related

- [ADR-052 DDD Appendix](ADR-052-appendix-ddd-bounded-contexts.md) — Bounded-context model (aggregates,
  entities, domain events) for ADR-052's Tauri desktop frontend; a companion document, not an
  independent decision, so it isn't in the index above
- [DDD Domain Models](../ddd/) — Bounded context definitions, aggregate roots, and ubiquitous language
- [User Guide](../user-guide.md) — Setup, API reference, and hardware instructions
- [Build Guide](../build-guide.md) — Building from source
