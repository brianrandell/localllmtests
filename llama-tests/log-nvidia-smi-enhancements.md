# `log-nvidia-smi.ps1` — Future Enhancement Backlog

Comparison against `nvidia-smi-mon.ps1` (a parallel logger script). This document captures features present in `nvidia-smi-mon.ps1` that could be backported into `log-nvidia-smi.ps1` later. Current `log-nvidia-smi.ps1` is frozen pending completion of the active benchmark phases (PCIe x16 → OcuLink → TB5) to preserve comparability across runs.

*Created: 2026-04-22*

---

## Worth Considering

### 1. Optional `-Duration <seconds>` parameter

Auto-stop after N seconds instead of requiring Ctrl+C.

- **Why:** Enables fire-and-forget logging from a wrapper script — e.g., spawn the logger for exactly the duration of an MLPerf run, then have it terminate on its own.
- **Implementation:** Default `0` = run until Ctrl+C; `> 0` = run for that many seconds.

### 2. End-of-run summary block

Track peak power, peak temp, peak VRAM, peak GPU util, plus power and temp averages in memory during the run. Print a formatted summary on exit.

- **Why:** Quick at-a-glance read of the run without opening the CSV in Excel or a notebook.
- **Implementation:** Running totals + max-so-far variables updated each sample; formatted `Write-Host` block in the `finally {}` section.
- **Sample output:**
  ```
  Peak Values:
    VRAM:  94.2 GB
    Power: 612W (avg: 485W)
    Temp:  72C (avg: 64C)
    GPU:   99%
  ```

### 3. Upfront GPU validation

Query `nvidia-smi -i $Gpu --query-gpu=name,memory.total --format=csv,noheader` at script start and error out cleanly if the GPU index is invalid.

- **Why:** Current script silently swallows errors (`2>$null`) and produces an empty CSV if `-GpuIndex` is mistyped. A defensive check upfront catches that immediately.
- **Bonus:** Also lets the startup banner print the GPU's actual name and VRAM total, which is useful documentation in the terminal history.

### 4. Live display overwrites a single line

Use `\r` + `-NoNewline` to update one status line every ~1s with an elapsed-seconds counter, rather than appending a new line every 10 samples.

- **Why:** Cosmetic, but much cleaner for long runs (80-minute llama-bench sessions would otherwise produce ~1900 status lines in the terminal history).

---

## Marginal

### 5. Configurable `-OutputDir` parameter

Instead of hardcoded `.\logs\nvidia-smi`.

- **When useful:** Only if you want to redirect to a session-specific folder. Low priority since the current convention works well.

### 6. Pre-computed `mem_pct` column

Memory-used-as-percentage-of-total.

- **Skip.** Trivially derivable post-hoc from `vram_used_mb / vram_total_mb`. Not a real gap.

### 7. Optional `-Label` (currently mandatory)

- **Skip.** Mandatory `-Label` is arguably the better design for your workflow — it forces label hygiene, which matters for traceability across the benchmark phases.

---

## Actively Better in Current Script — Do NOT Change

### Timestamp source

Current script uses nvidia-smi's internal `timestamp` query field (the timestamp of the sample itself). `nvidia-smi-mon.ps1` generates its own `Get-Date -Format "o"` timestamp post-query.

- **Keep current behavior.** The sample's own timestamp is more accurate than a PowerShell-generated one taken after the `nvidia-smi` invocation returns.

### `name` and `index` columns per row

Redundant (they don't change during a run) but harmless, and handy when concatenating CSVs from multi-GPU runs or across sessions.

- **Keep.**

---

## Recommended Implementation Order (When the Time Comes)

If/when you decide to enhance, the highest-value combination is **#1 + #2 together**:

- `-Duration` turns the logger into something you can fire-and-forget from a benchmark wrapper.
- The summary block gives you peak/avg readouts without post-processing.

Add **#3** (GPU validation) at the same time — it's ~10 lines and closes a silent-failure mode.

Leave **#4** (single-line live display) for last — pure cosmetics.

---

## Notes on Script Freeze

`log-nvidia-smi.ps1` has been used as-is across:
- RTX PRO 6000 PCIe x8 baseline (Mar 8)
- RTX 5090 TB5 results
- (in progress) RTX PRO 6000 PCIe x16

Any enhancement should happen **after** the full interface phase set (PCIe → OcuLink → TB5) is complete, so all phase-to-phase comparisons use the same logger version and CSV schema. A schema change mid-campaign would complicate cross-phase analysis.
