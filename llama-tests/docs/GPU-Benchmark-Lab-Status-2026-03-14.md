# GPU Benchmark Lab Status Report
## As of March 14, 2026

---

## Lab Overview

Brian runs a personal AI and hardware benchmarking lab focused on systematic, rigorous performance characterization across hardware configurations, interfaces, and AI workloads. Primary interest: large model inference, GPU-accelerated compute, and cross-platform comparisons.

---

## Primary Test Machine: Gwen

| Component | Specification |
|-----------|---------------|
| **Motherboard** | ASUS ProArt Z890-CREATOR WIFI |
| **CPU** | Intel Core Ultra 9 285K |
| **RAM** | 128 GB DDR5-5600 |
| **OS** | Windows 11 Pro for Workstations |
| **Primary GPU** | RTX PRO 6000 Blackwell Workstation Edition (96 GB) — PCIe x8 |
| **Secondary GPU** | RTX 5090 (32 GB) — via Thunderbolt 5 / Razer Core X V2 |
| **Thunderbolt** | TB5 Barlow Ridge + TB4 Arrow Lake integrated |

### ⚠️ CRITICAL: Dual-Driver Configuration Required

The RTX PRO 6000 and RTX 5090 require **different driver INFs**:

| GPU | Driver INF | Driver Type | Version |
|-----|------------|-------------|---------|
| RTX PRO 6000 | oem17.inf (nv_dispwi.inf) | RTX Enterprise | 591.59 |
| RTX 5090 | oem60/61.inf (nvmdsi/nv_dispsi.inf) | GeForce Game Ready/Studio | 595.79 |

**Current working configuration:** Driver 595.79, CUDA 13.2

The enterprise driver does NOT include the RTX 5090 device ID (`PCI\VEN_10DE&DEV_2B85`). Both driver packages must be installed for dual-GPU operation.

### Other Lab Machines
| Name | OS | Processor | Primary GPU | VRAM | AI RAM Type |
|------|-----|-----------|-------------|------|-------------|
| Raven | Windows 11 Pro | AMD Ryzen 9 5950X | RTX 4090 | 24 GB | Dedicated |
| ScarlettWitch | Windows 10 Pro | Intel Xeon W-3245 | RTX 3090 | 24 GB | Dedicated |
| WidowM3 | macOS Sequoia | Apple M3 Max | M3 Max | 128 GB | Shared |
| AngelX | Windows 11 Pro | Snapdragon X Elite | Adreno X1-85 | 64 GB | Shared |
| M4Pro | macOS Tahoe | Apple M4 Pro | M4 Pro | 24 GB | Shared |
| Natasha | macOS Sequoia | Intel Xeon W-3245 | AMD Radeon Pro W6800X Duo | 64 GB | Dedicated |

---

## Completed Benchmarks

### 1. 3DMark — RTX PRO 6000 (PCIe x8)

**49 total runs across 1080p, 4K, 5K, 6K resolutions**

| Test | Best Score | Average | Resolution Impact |
|------|------------|---------|-------------------|
| Time Spy | 40,069 | 39,745 | <1.2% variance |
| Time Spy Extreme | 24,393 | 24,248 | <1.2% variance |
| Port Royal | 35,963 | 35,754 | <1.2% variance |
| SpeedWay | 15,565 | 15,458 | <1.2% variance |

**Key Finding:** Output resolution has negligible impact on 3DMark scores (<1.2%). 3DMark renders internally at fixed resolution. **Single-resolution testing is sufficient for all future comparisons.**

**GPU Metrics:**
- Peak Power: 603W (Time Spy Extreme)
- Peak Temp: 84°C (no throttling)
- VRAM Usage: 1.9–7.5 GB (even at 6K, only 8% of 96 GB)

---

### 2. llama-bench — RTX PRO 6000 (PCIe x8)

**19 models, 10 repeats each, <1% stddev variance**

| Model | Size | PP tok/s | TG tok/s | VRAM | Peak Power |
|-------|------|----------|----------|------|------------|
| Qwen 2.5 Coder 7B Q4 | 4.4 GB | 13,478 | 234 | 5.3 GB | 598W |
| Llama 3.1 8B Q4 | 4.6 GB | 12,162 | 218 | 5.7 GB | 596W |
| Ministral 8B Q4 | 4.6 GB | 11,470 | 210 | 5.7 GB | 601W |
| GPT-OSS 20B MXFP4 | 11.3 GB | 11,277 | 287 | 12.2 GB | 561W |
| Nemotron-3-Nano 30B MoE Q4 | 21.3 GB | 9,209 | 278 | 22.6 GB | 586W |
| Phi-4 14B Q4 | 8.4 GB | 6,907 | 133 | 9.8 GB | 602W |
| GPT-OSS 120B MoE MXFP4 | 59.0 GB | 5,543 | 206 | 61.2 GB | 499W |
| Qwen 3.5 35B MoE Q4 ★ | 19.2 GB | 5,275 | 166 | 20.5 GB | 406W |
| Qwen 2.5 Coder 32B Q4 | 18.5 GB | 3,179 | 64 | 20.1 GB | 601W |
| Qwen 3.5 27B Dense Q6 ★ | 20.9 GB | 2,602 | 51 | 21.9 GB | 582W |
| Qwen 2.5 Coder 32B Q6 | 25.0 GB | 2,608 | 50 | 26.6 GB | 609W |
| Qwen 3.5 122B MoE Q4 ★ | 69.2 GB | 2,520 | 103 | 71.9 GB | 531W |
| Llama 3.1 70B Q8 | 69.8 GB | 1,514 | 20 | 72.2 GB | 602W |
| Qwen 2.5 72B Q8 | 72.0 GB | 1,485 | 19 | 74.2 GB | 609W |
| Qwen 2.5 72B Q4 | 44.2 GB | 1,472 | 30 | 46.3 GB | 604W |
| DeepSeek-R1 70B Q4 | 39.6 GB | 1,467 | 32 | 41.8 GB | 605W |
| Llama 3.1 70B Q6 | 53.9 GB | 1,200 | 24 | 56.2 GB | 607W |
| Command-R+ 104B Q4 | 58.4 GB | 1,058 | 23 | 61.8 GB | 602W |
| Command-R+ 104B Q6 | 79.3 GB | 867 | 17 | 83.1 GB | 604W |

★ = New Qwen 3.5 models (Feb 24, 2026 release)

**Key Findings:**
- MoE models excel: GPT-OSS 120B at 206 tok/s, Qwen 3.5 122B at 103 tok/s
- Very low variance across 10 repeats — excellent consistency
- Command-R+ 104B Q6 at 83.1 GB VRAM is the largest model tested

---

### 3. llama-bench — RTX 5090 via TB5 (Quick Test, March 14)

Single validation run after driver fix:

| Model | PP tok/s | TG tok/s | vs RTX PRO 6000 |
|-------|----------|----------|-----------------|
| Llama 3.1 8B Q4 | 11,127 | 197 | 91% PP / 90% TG |

Full benchmark run in progress.

---

### 4. MLPerf Client — RTX PRO 6000 (Supplementary)

**2 runs, averaged results**

| Model | EP | Avg tok/s | Avg TTFT |
|-------|-----|-----------|----------|
| Phi 3.5 3.8B | TensorRT | 335 | 77ms |
| Phi 3.5 3.8B | DirectML | 322 | 63ms |
| Llama 3.1 8B | TensorRT | 241 | 92ms |
| Llama 3.1 8B | DirectML | 238 | 91ms |
| Llama 2 7B | DirectML | 239 | 78ms |
| Phi 4 14B | TensorRT | 144 | 127ms |
| Phi 4 14B | DirectML | 139 | 146ms |

**Notes:**
- MLPerf Client only supports small models (up to 14B)
- TensorRT vs DirectML: similar throughput, TensorRT has longer compilation time
- llama-bench Llama 3.1 8B (237 tok/s) closely matches MLPerf (238-241 tok/s) — good cross-validation
- Use as supplementary standardized benchmark; custom llama-bench is the primary differentiator

---

## Models & Files

### Downloaded Models (802.5 GB total, 36 GGUF files)
Location: `E:\llama-tests\gguf`

**11GB Tier:** Llama 3.1 8B Q4, Qwen 2.5 Coder 7B Q4, Ministral 8B Q4

**24GB Tier:** Phi-4 14B Q4, Qwen 2.5 Coder 32B Q4, Nemotron-3-Nano 30B-A3B Q4, Qwen 3.5-35B-A3B Q4

**32GB Tier:** Qwen 2.5 Coder 32B Q6, Qwen 3.5-27B Q6

**96GB Tier:** DeepSeek-R1 70B Q4, Qwen 2.5 72B Q4, Qwen 2.5 72B Q8 (split), Llama 3.1 70B Q6 (split), Llama 3.1 70B Q8 (split), Command-R+ 104B Q4 (split), Command-R+ 104B Q6 (split), Qwen 3.5-122B-A10B Q4 (split), GPT-OSS 120B MXFP4 (split), GPT-OSS 20B MXFP4

**Vision Projectors:** Qwen 3.5-35B-A3B-mmproj-BF16.gguf, Qwen 3.5-122B-A10B-mmproj-BF16.gguf

### llama.cpp Version
- Current: **b8182** (built for CUDA 13.1, compatible with CUDA 13.2)
- Location: `E:\llama-tests\llama-cpp\llama-bench.exe`
- Backup of old build: `E:\llama-tests\llama-cpp-b4691-backup`

---

## Scripts & Tools

### llama-bench Script
- Location: `E:\llama-tests\run-llama-bench.ps1` (also v2 variant)
- Features: 19 models, 4 VRAM tiers, -ListModels flag, handles split files, 10 repeats default
- GPU selection: `-Gpu 0` for RTX PRO 6000, `-Gpu 1` for RTX 5090
- Output: `.\logs\{mode}-{timestamp}\`

### nvidia-smi Logger
- Location: `E:\llama-tests\log-nvidia-smi.ps1`
- Usage: `.\log-nvidia-smi.ps1 -Label "3dmark-timespy-1080p"`
- Output: `.\logs\nvidia-smi\nvidia-smi-gpu0-{label}-{timestamp}.csv`
- Captures: clocks, power, power limit, utilization, VRAM, temp, fan

### Model Download Script
- Location: `download-all-models-v3.ps1`
- Uses HF CLI exclusively, category filter (-Category 24GB/32GB/96GB/All)

### ThunderboltReport.ps1 v2.0
- Generalized PowerShell script for Thunderbolt/USB4 controller topology analysis
- Cleans ghosted device entries via pnputil

### Get-DisplayConfig.ps1 (NEW)
Maps monitors to GPUs by adapter ID:
```powershell
# Get all monitors with connection info
Get-CimInstance -Namespace root\wmi -ClassName WmiMonitorConnectionParams | ForEach-Object {
    $path = $_.InstanceName
    $adapterId = ($path -split '\\')[2] -replace '&UID.*', ''
    
    $monitorId = Get-CimInstance -Namespace root\wmi -ClassName WmiMonitorID | 
        Where-Object { $_.InstanceName -eq $path }
    $name = if ($monitorId) { 
        -join ($monitorId.UserFriendlyName | Where-Object {$_ -ne 0} | ForEach-Object {[char]$_}) 
    } else { "Unknown" }
    
    [PSCustomObject]@{
        Monitor = $name
        AdapterID = $adapterId
        Connection = switch ($_.VideoOutputTechnology) {
            5 {"DisplayPort"}; 6 {"DisplayPort"}; 10 {"HDMI"}; 11 {"Internal/eDP"}
            default {"Type $($_.VideoOutputTechnology)"}
        }
    }
} | Sort-Object AdapterID | Format-Table -AutoSize
```
Monitors with the same AdapterID are on the same GPU.

---

## Key Methodology Learnings

1. **3DMark resolution testing is unnecessary** — scores render at fixed internal resolution; single resolution sufficient

2. **Natural cooldown is adequate** — 10-15 minute cable/enclosure swap time between interface configs provides sufficient thermal normalization

3. **Benchmark role separation:**
   - MLPerf Client = standardized small-model comparison
   - Custom llama-bench = primary large-model benchmark (the differentiator for high-VRAM cards)

4. **Driver management is complex for mixed GPU configs:**
   - RTX PRO 6000 (workstation) + RTX 5090 (consumer) require different driver INFs
   - Enterprise driver alone does NOT support RTX 5090
   - Must install GeForce driver to get 5090 support, which also updates the shared NVIDIA components
   - Keep Windows driver updates policy OFF

5. **DDU is powerful but requires careful follow-up** — after DDU, ensure both driver packages are installed for dual-GPU configs

---

## Streamlined Interface Comparison Test Plan

For each GPU/interface combo (~3 hours total):

| Interface | Tests | Runs | Est. Time |
|-----------|-------|------|-----------|
| PCIe x16/x8 | 4 3DMark tests | 3 each | ~45 min |
| *swap cables (~15 min cooldown)* |||
| Thunderbolt 5 | 4 3DMark tests | 3 each | ~45 min |
| *swap cables (~15 min cooldown)* |||
| Oculink | 4 3DMark tests | 3 each | ~45 min |

**Pre-flight check:** Verify GPU temp <50°C before starting each batch:
```powershell
nvidia-smi --query-gpu=temperature.gpu --format=csv,noheader
```

For llama-bench interface comparison: use `-Repeats 5` to save time.

---

## Pending / Next Steps

1. **RTX 5090 TB5 full benchmark** — currently running (March 14)

2. **Interface comparison testing:** PCIe vs Thunderbolt 5 vs Oculink for RTX PRO 6000 / RTX 5090

3. **Multi-GPU testing:** RTX 4090, RTX 3090 benchmarks

4. **Cross-machine AI benchmarking:** 7 machines using Qwen 2.5 14B (text) and Llama 3.2 Vision 11B (multimodal)

5. **Natasha triple-boot setup:** macOS Tahoe / Windows 11 LTSC / Linux + ROCm (pending hardware work)

6. **AngelX GPU/NPU acceleration:** LM Studio, ONNX Runtime with QNN execution provider

7. **8K 3DMark testing:** Pending proper DP-to-HDMI 8K cable arrival

---

## Recent Issues Resolved

### March 14, 2026: CUDA Init Failure & Dual-Driver Discovery

**Symptom:** `ggml_cuda_init: failed to initialize CUDA: (null)` — llama-bench ran on CPU instead of GPU

**Root Cause Chain:**
1. March 10: Code 31 driver conflict fixed with DDU → reinstalled enterprise driver 591.59
2. Windows later installed GeForce driver 572.83 (CUDA 12.8) which broke llama-bench (built for CUDA 13.1)
3. Reinstalling 591.59 fixed RTX PRO 6000 but RTX 5090 showed Code 31
4. Discovery: Enterprise driver INF (nv_dispwi.inf) does NOT include RTX 5090 device ID (DEV_2B85)

**Fix:**
1. Install GeForce Game Ready/Studio driver (595.79) for RTX 5090 support
2. This updated shared components to CUDA 13.2 (backward compatible with 13.1 llama-bench build)
3. Both GPUs now work with different INFs from the same driver package

**Final State:**
```
nvidia-smi: Driver 595.79, CUDA 13.2
GPU 0: RTX PRO 6000 (oem17.inf - enterprise)
GPU 1: RTX 5090 (oem60/61.inf - GeForce)
```

### March 10, 2026: Driver Conflict (Code 31)

**Symptom:** Code 31 errors, GPUs alternating between working/broken states

**Cause:** Old driver (oem40.inf, version 7688 from June 2025) conflicting with current driver

**Fix:** 
1. DDU clean in Safe Mode
2. Reinstall enterprise driver 591.59
3. (Later required GeForce driver for 5090 — see March 14)

**Prevention:** Keep Windows driver updates policy OFF

---

## Driver Store Reference

Current working driver INFs (as of March 14, 2026):

| INF | Original Name | Provider | Version | Purpose |
|-----|---------------|----------|---------|---------|
| oem19.inf | iigd_dch.inf | Intel | 32.0.101.8509 | Intel iGPU |
| oem17.inf | nv_dispwi.inf | NVIDIA | 32.0.15.9159 | RTX PRO 6000 (Enterprise) |
| oem60.inf | nvmdsi.inf | NVIDIA | 32.0.15.9579 | RTX 5090 (GeForce) |
| oem61.inf | nv_dispsi.inf | NVIDIA | 32.0.15.9579 | RTX 5090 (GeForce) |

**Watch for conflicts:** Any old `nvmd.inf` or driver version 7xxx should be removed with:
```powershell
pnputil /delete-driver oemXX.inf /force
```

---

## Quick Reference Commands

```powershell
# Check GPU status
nvidia-smi

# Check GPU temp before testing
nvidia-smi --query-gpu=temperature.gpu --format=csv,noheader

# List CUDA devices for llama-bench
.\llama-cpp\llama-bench.exe --list-devices

# List available models
.\run-llama-bench.ps1 -ListModels

# Run benchmark on RTX PRO 6000 (GPU 0)
.\run-llama-bench.ps1 -Mode "6000-pcie" -Gpu 0 -Repeats 5

# Run benchmark on RTX 5090 (GPU 1)
.\run-llama-bench.ps1 -Mode "5090-tb5" -Gpu 1 -Repeats 5

# Log nvidia-smi during external benchmark
.\log-nvidia-smi.ps1 -Label "3dmark-timespy-rtx5090"

# Scan for ghosted devices
pnputil /scan-devices

# List display drivers
pnputil /enum-drivers /class "Display"

# Check for error devices
Get-PnpDevice | Where-Object { $_.Status -eq 'Error' }

# Check nvidia-smi display status per GPU
nvidia-smi --query-gpu=index,name,display_active --format=csv
```

---

## Current Display Configuration (Gwen)

| Monitor | Connection | GPU |
|---------|------------|-----|
| SAMSUNG (8K) | HDMI | RTX 5090 (TB5) |
| StudioDisplay (5K) | USB-C→DP | RTX 5090 (TB5) |
| VX1655-OLED (4K) | mini-HDMI→DP | RTX 5090 (TB5) |
| BenQ XL2420TX | DisplayPort | Intel iGPU |

All displays at 200% HiDPI, 60Hz. Intel iGPU display used for monitoring during GPU benchmarks.

---

*Generated: March 14, 2026*
