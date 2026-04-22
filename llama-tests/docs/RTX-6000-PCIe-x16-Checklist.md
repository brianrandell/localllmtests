# RTX PRO 6000 Blackwell — PCIe x16 Test Checklist
## Gwen | Full Baseline Suite

---

## Phase 0 — Hardware Setup

- [ ] **Power down Gwen completely** (full shutdown, not sleep)
- [ ] **Remove the dual 25GbE NIC** from its PCIe slot
- [ ] **Confirm RTX PRO 6000 is seated in the primary x16 slot** (slot closest to CPU)
- [ ] **Reseat if needed** — remove and reinstall to ensure clean contact
- [ ] **Plug BenQ XL2420TX into the RTX PRO 6000** via DisplayPort
- [ ] **Power on and boot to Windows**
- [ ] Verify GPU is recognized: open Device Manager → Display Adapters → confirm RTX PRO 6000 shows, no error codes
- [ ] Run: `nvidia-smi` — confirm driver 595.79, GPU 0 = RTX PRO 6000
- [ ] Run: `nvidia-smi --query-gpu=index,name,pcie.link.width.current --format=csv` — **confirm link width = 16**
- [ ] Check GPU temp is below 50°C before starting:
  ```powershell
  nvidia-smi --query-gpu=temperature.gpu --format=csv,noheader
  ```

---

## Phase 1 — 3DMark

**Settings:** 1080p (BenQ native), DisplayPort, display connected to RTX PRO 6000, Performance preset for all tests.

Start nvidia-smi logger before each test batch:
```powershell
.\log-nvidia-smi.ps1 -Label "3dmark-timespy-6000-pcie-x16"
```
Stop logger after each test batch (Ctrl+C).

### 1A — Time Spy
- [ ] Run 1 → record score
- [ ] Run 2 → record score
- [ ] Run 3 → record score
- [ ] Save all 3 `.3dmark-result` files → folder: `3dmark\6000-pcie-x16\timespy\`

### 1B — Time Spy Extreme
- [ ] Run 1 → record score
- [ ] Run 2 → record score
- [ ] Run 3 → record score
- [ ] Save all 3 `.3dmark-result` files → folder: `3dmark\6000-pcie-x16\timespy-extreme\`

### 1C — Port Royal
- [ ] Run 1 → record score
- [ ] Run 2 → record score
- [ ] Run 3 → record score
- [ ] Save all 3 `.3dmark-result` files → folder: `3dmark\6000-pcie-x16\port-royal\`

### 1D — Speed Way
- [ ] Run 1 → record score
- [ ] Run 2 → record score
- [ ] Run 3 → record score
- [ ] Save all 3 `.3dmark-result` files → folder: `3dmark\6000-pcie-x16\speedway\`

**After Phase 1:** Let GPU cool to <50°C before proceeding.

---

## Phase 2 — llama-bench (Full Suite)

**Mode name to use:** `Gwen-6000-pcie-x16`

```powershell
# Verify GPU 0 is available to llama-bench
.\llama-cpp\llama-bench.exe --list-devices

# Verify all 19 models are present
.\run-llama-bench.ps1 -ListModels

# Start nvidia-smi logger in a separate terminal
.\log-nvidia-smi.ps1 -Label "llama-bench-6000-pcie-x16"

# Run full suite (10 repeats, GPU 0, ~80 min)
.\run-llama-bench.ps1 -Mode "Gwen-6000-pcie-x16" -Gpu 0 -Repeats 10
```

- [ ] Confirm all 19 models listed before starting
- [ ] nvidia-smi logger running in separate terminal
- [ ] Benchmark running — do not touch system during run
- [ ] Run complete — note timestamp
- [ ] Stop nvidia-smi logger
- [ ] Confirm output files exist:
  - `.\logs\Gwen-6000-pcie-x16-{timestamp}\results.csv`
  - `.\logs\Gwen-6000-pcie-x16-{timestamp}\summary.csv`
  - `.\logs\Gwen-6000-pcie-x16-{timestamp}\run-summary.txt`
- [ ] Copy output folder to backup location

**After Phase 2:** Let GPU cool to <50°C before proceeding.

---

## Phase 3 — MLPerf Client (Supplementary)

- [ ] Launch MLPerf Client
- [ ] Select GPU: RTX PRO 6000
- [ ] Run 1 (full default model set) → save results
- [ ] Run 2 (full default model set) → save results
- [ ] Save both result files → folder: `mlperf\6000-pcie-x16\`

---

## Phase 4 — Wrap-Up

- [ ] All 3DMark result files saved and organized
- [ ] llama-bench results.csv and summary.csv confirmed
- [ ] MLPerf results saved
- [ ] Upload results.csv, summary.csv, and run-summary.txt here for analysis
- [ ] Update lab status document with x16 scores

---

## Reference — Expected Scores (x8 Baseline for Comparison)

| Test | x8 Baseline (Mar 8) | x16 Target |
|------|---------------------|------------|
| Time Spy | ~39,745 avg | TBD |
| Time Spy Extreme | ~24,248 avg | TBD |
| Port Royal | ~35,754 avg | TBD |
| SpeedWay | ~15,458 avg | TBD |
| llama-bench PP (8B Q4) | 12,162 tok/s | TBD |
| llama-bench TG (8B Q4) | 218 tok/s | TBD |

> **Note:** 3DMark scores are not expected to differ significantly between x8 and x16 — the GPU is not bandwidth-limited for rasterization workloads. The meaningful delta will show in llama-bench prompt processing (PP) for large models.

---

*Checklist version: 2026-04-06 | Phase: Gwen PCIe x16 Baseline*
