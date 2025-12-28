<#
.SYNOPSIS
    Runs llama-bench.exe on multiple GGUF models with nvidia-smi monitoring.
    Auto-detects GPU and selects appropriate models based on VRAM.

.DESCRIPTION
    Hardware comparison benchmark using llama-bench.exe.
    Captures GPU metrics (VRAM, power, temp, utilization) during each run.
    
    GPU Detection:
    - 32GB+ (RTX 5090): Runs 4 models including Q6_K large model
    - 24GB (RTX 3090/4090): Runs 3 models (Q4_K_M only)

.PARAMETER Mode
    Test mode identifier (e.g., "5090-pcie", "4090-pcie", "3090-pcie")

.PARAMETER Repeats
    Number of llama-bench repetitions per model (default: 10)

.EXAMPLE
    .\run-llama-bench.ps1 -Mode "5090-pcie"
    .\run-llama-bench.ps1 -Mode "4090-pcie" -Repeats 5
#>

param(
    [Parameter(Mandatory=$true)]
    [string]$Mode,
    
    [int]$Repeats = 10,
    
    [int]$PromptTokens = 2048,
    
    [int]$GenTokens = 512,
    
    [int]$SmiIntervalMs = 250
)

# Paths
$LlamaBenchExe = ".\llama-cpp\llama-bench.exe"
$GgufDir = ".\gguf"

# ============================================
# GPU Detection
# ============================================
Write-Host "Detecting GPU..." -ForegroundColor Cyan

$gpuInfo = nvidia-smi --query-gpu=name,memory.total --format=csv,noheader,nounits 2>&1
if ($LASTEXITCODE -ne 0) {
    Write-Error "nvidia-smi failed. Is an NVIDIA GPU present?"
    exit 1
}

$gpuParts = $gpuInfo -split ","
$gpuName = $gpuParts[0].Trim()
$gpuVramMb = [int]$gpuParts[1].Trim()
$gpuVramGb = [math]::Round($gpuVramMb / 1024, 1)

Write-Host "  GPU: $gpuName"
Write-Host "  VRAM: $gpuVramGb GB ($gpuVramMb MB)"

# ============================================
# Model Selection Based on VRAM
# ============================================

# Base models (fit on 24GB cards)
$Models24GB = @(
    "Ministral-3-8B-Instruct-2512-Q4_K_M.gguf",
    "phi-4-Q4_K_M.gguf",
    "qwen2.5-coder-32b-instruct-q4_k_m.gguf"
)

# Additional model for 32GB+ cards
$Model32GBOnly = "Qwen2.5-Coder-32B-Instruct-Q6_K.gguf"

# Select models based on VRAM
if ($gpuVramMb -ge 30000) {
    # 32GB+ card (5090, etc.)
    $Models = $Models24GB + @($Model32GBOnly)
    Write-Host "  Profile: 32GB+ (4 models)" -ForegroundColor Green
} else {
    # 24GB card (3090, 4090, etc.)
    $Models = $Models24GB
    Write-Host "  Profile: 24GB (3 models)" -ForegroundColor Yellow
}

Write-Host ""

# ============================================
# Verify Models Exist
# ============================================
$MissingModels = @()
foreach ($ModelFile in $Models) {
    $ModelPath = Join-Path $GgufDir $ModelFile
    if (-not (Test-Path $ModelPath)) {
        $MissingModels += $ModelFile
    }
}

if ($MissingModels.Count -gt 0) {
    Write-Host "Missing model files:" -ForegroundColor Red
    foreach ($m in $MissingModels) {
        Write-Host "  - $m" -ForegroundColor Red
    }
    Write-Host ""
    Write-Host "Download missing models to: $GgufDir" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "Download links:" -ForegroundColor Cyan
    Write-Host "  Ministral-3:  https://huggingface.co/unsloth/Ministral-3-8B-Instruct-2512-GGUF/resolve/main/Ministral-3-8B-Instruct-2512-Q4_K_M.gguf"
    Write-Host "  Phi-4:        https://huggingface.co/lmstudio-community/phi-4-GGUF/resolve/main/phi-4-Q4_K_M.gguf"
    Write-Host "  Qwen 32B Q4:  https://huggingface.co/Qwen/Qwen2.5-Coder-32B-Instruct-GGUF (use huggingface-cli)"
    Write-Host "  Qwen 32B Q6:  https://huggingface.co/bartowski/Qwen2.5-Coder-32B-Instruct-GGUF/resolve/main/Qwen2.5-Coder-32B-Instruct-Q6_K.gguf"
    exit 1
}

# ============================================
# Setup Logging
# ============================================
$Timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
$LogDir = ".\logs\$Timestamp-$Mode"
New-Item -ItemType Directory -Path $LogDir -Force | Out-Null

$CsvFile = "$LogDir\llama-bench-results-$Mode.csv"
$SummaryFile = "$LogDir\llama-bench-summary-$Mode.csv"
$RunSummaryFile = "$LogDir\run-summary-$Mode.txt"

# Initialize CSV with headers
$CsvHeaders = "mode,model,model_size_gb,test,tokens,repetitions,avg_tok_s,stddev_tok_s,gpu_mem_max_mb,gpu_power_max_w,gpu_power_mean_w,gpu_temp_max_c,gpu_util_max_pct,gpu_util_mean_pct,gpu_samples,run_timestamp"
$CsvHeaders | Out-File -FilePath $CsvFile -Encoding UTF8

# Capture system info
$NvidiaSmiInfo = & nvidia-smi 2>&1

# Write run header
@"
=== RUN HEADER ===
Timestamp: $(Get-Date -Format "o")
Mode: $Mode
GPU: $gpuName ($gpuVramGb GB)
Tool: llama-bench.exe
Prompt Tokens: $PromptTokens
Gen Tokens: $GenTokens
Repeats: $Repeats
SMI Interval: ${SmiIntervalMs}ms
Models: $($Models -join ', ')

nvidia-smi:
$NvidiaSmiInfo
==================
"@ | Out-File -FilePath $RunSummaryFile -Encoding UTF8

Write-Host "llama-bench Hardware Comparison"
Write-Host "================================"
Write-Host "Mode: $Mode"
Write-Host "GPU: $gpuName ($gpuVramGb GB)"
Write-Host "Models: $($Models.Count)"
Write-Host "Repeats: $Repeats"
Write-Host "SMI Interval: ${SmiIntervalMs}ms"
Write-Host "Output: $LogDir"
Write-Host ""

# ============================================
# GPU Monitor Functions
# ============================================
function Start-GpuMonitor {
    param([string]$LogFile, [int]$IntervalMs = 500)
    
    $logDir = Split-Path -Parent $LogFile
    if (-not (Test-Path $logDir)) { New-Item -ItemType Directory -Path $logDir -Force | Out-Null }
    
    $scriptPath = Join-Path ([System.IO.Path]::GetTempPath()) "nvidia-smi-logger-$([Guid]::NewGuid().ToString('N').Substring(0,8)).ps1"
    
    $scriptContent = @"
`$ErrorActionPreference = 'SilentlyContinue'
`$outFile = '$($LogFile -replace "'", "''")'
while (`$true) {
    `$ts = Get-Date -Format o
    `$smi = nvidia-smi --query-gpu=memory.used,memory.total,utilization.gpu,power.draw,temperature.gpu --format=csv,noheader,nounits 2>&1
    `$line = "`$ts,`$smi"
    [System.IO.File]::AppendAllText(`$outFile, `$line + [Environment]::NewLine, [System.Text.Encoding]::UTF8)
    Start-Sleep -Milliseconds $IntervalMs
}
"@
    
    [System.IO.File]::WriteAllText($scriptPath, $scriptContent, [System.Text.Encoding]::UTF8)
    
    $proc = Start-Process -FilePath "powershell.exe" `
        -ArgumentList "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", $scriptPath `
        -WindowStyle Hidden `
        -PassThru
    
    return $proc
}

function Get-GpuMetrics {
    param([string]$LogFile)
    
    $metrics = @{
        MemMaxMb = 0
        PowerMaxW = 0
        PowerMeanW = 0
        TempMaxC = 0
        UtilMaxPct = 0
        UtilMeanPct = 0
        Samples = 0
    }
    
    if (Test-Path $LogFile) {
        $lines = Get-Content $LogFile -ErrorAction SilentlyContinue | Select-Object -Skip 1
        $powerSum = 0
        $utilSum = 0
        $count = 0
        
        foreach ($line in $lines) {
            $parts = $line -split ","
            if ($parts.Count -ge 6) {
                try {
                    # nvidia-smi returns: memory.used, memory.total, utilization.gpu, power.draw, temperature.gpu
                    # After timestamp, indices are: [1]=mem_used, [2]=mem_total, [3]=util, [4]=power, [5]=temp
                    $memUsed = [double]($parts[1].Trim()) 
                    $util = [double]($parts[3].Trim())
                    $power = [double]($parts[4].Trim())
                    $temp = [double]($parts[5].Trim())
                    
                    if ($memUsed -gt $metrics.MemMaxMb) { $metrics.MemMaxMb = $memUsed }
                    if ($power -gt $metrics.PowerMaxW) { $metrics.PowerMaxW = $power }
                    if ($temp -gt $metrics.TempMaxC) { $metrics.TempMaxC = $temp }
                    if ($util -gt $metrics.UtilMaxPct) { $metrics.UtilMaxPct = $util }
                    
                    $powerSum += $power
                    $utilSum += $util
                    $count++
                } catch {
                    # Skip lines that can't be parsed
                }
            }
        }
        
        if ($count -gt 0) {
            $metrics.PowerMeanW = [math]::Round($powerSum / $count, 1)
            $metrics.UtilMeanPct = [math]::Round($utilSum / $count, 1)
            $metrics.Samples = $count
        }
    }
    
    return $metrics
}

function Parse-LlamaBenchOutput {
    param([string]$Output)
    
    $results = @()
    $lines = $Output -split "`n"
    
    foreach ($line in $lines) {
        # Match lines like: | model | size | params | backend | ngl | test | t/s |
        # Note: ± may appear as various encodings (±, ┬▒, etc.)
        if ($line -match '^\|\s*([^|]+)\s*\|\s*([\d.]+)\s*GiB\s*\|\s*([\d.]+)\s*B\s*\|\s*(\w+)\s*\|\s*(\d+)\s*\|\s*(pp\d+|tg\d+)\s*\|\s*([\d.]+)\s*.{1,3}\s*([\d.]+)\s*\|') {
            $results += @{
                Model = $Matches[1].Trim()
                SizeGiB = [double]$Matches[2]
                Params = $Matches[3]
                Backend = $Matches[4]
                NGL = $Matches[5]
                Test = $Matches[6]
                TokPerSec = [double]$Matches[7]
                StdDev = [double]$Matches[8]
            }
        }
    }
    
    return $results
}

# ============================================
# Main Benchmark Loop
# ============================================
$ModelIndex = 0
$AllResults = @()

foreach ($ModelFile in $Models) {
    $ModelIndex++
    $ModelPath = Join-Path $GgufDir $ModelFile
    
    $ModelName = [System.IO.Path]::GetFileNameWithoutExtension($ModelFile)
    Write-Host "[$ModelIndex/$($Models.Count)] Model: $ModelName"
    
    # Create model-specific log dir
    $ModelLogDir = Join-Path $LogDir $ModelName.Replace(".", "_")
    New-Item -ItemType Directory -Path $ModelLogDir -Force | Out-Null
    
    # Start GPU monitor
    $GpuLogFile = Join-Path $ModelLogDir "nvidia-smi.csv"
    "timestamp,mem_used_mb,mem_total_mb,util_pct,power_w,temp_c" | Out-File -FilePath $GpuLogFile -Encoding UTF8
    $GpuProc = Start-GpuMonitor -LogFile $GpuLogFile -IntervalMs $SmiIntervalMs
    
    # Small delay to ensure monitoring starts
    Start-Sleep -Milliseconds 500
    
    # Run llama-bench
    Write-Host "  Running llama-bench (pp$PromptTokens, tg$GenTokens, r$Repeats)..."
    $BenchOutput = & $LlamaBenchExe -m $ModelPath -p $PromptTokens -n $GenTokens -r $Repeats 2>&1 | Out-String
    
    # Stop GPU monitor
    if ($GpuProc -and -not $GpuProc.HasExited) {
        Stop-Process -Id $GpuProc.Id -Force -ErrorAction SilentlyContinue
    }
    
    # Save raw output
    $BenchOutput | Out-File -FilePath (Join-Path $ModelLogDir "llama-bench-output.txt") -Encoding UTF8
    
    # Parse results
    $ParsedResults = Parse-LlamaBenchOutput -Output $BenchOutput
    
    # Get GPU metrics
    $GpuMetrics = Get-GpuMetrics -LogFile $GpuLogFile
    
    # Get model file size
    $FileSizeGb = [math]::Round((Get-Item $ModelPath).Length / 1GB, 2)
    
    # Output results
    foreach ($result in $ParsedResults) {
        Write-Host "    $($result.Test): $($result.TokPerSec) ± $($result.StdDev) tok/s"
        
        # Add to CSV
        $CsvLine = "$Mode,$ModelName,$FileSizeGb,$($result.Test),$($result.Test -replace '[^\d]',''),$Repeats,$($result.TokPerSec),$($result.StdDev),$($GpuMetrics.MemMaxMb),$($GpuMetrics.PowerMaxW),$($GpuMetrics.PowerMeanW),$($GpuMetrics.TempMaxC),$($GpuMetrics.UtilMaxPct),$($GpuMetrics.UtilMeanPct),$($GpuMetrics.Samples),$(Get-Date -Format 'o')"
        $CsvLine | Out-File -FilePath $CsvFile -Append -Encoding UTF8
        
        $AllResults += [PSCustomObject]@{
            Mode = $Mode
            Model = $ModelName
            SizeGb = $FileSizeGb
            Test = $result.Test
            TokPerSec = $result.TokPerSec
            StdDev = $result.StdDev
            GpuMemMb = $GpuMetrics.MemMaxMb
            GpuPowerW = $GpuMetrics.PowerMaxW
            GpuPowerMeanW = $GpuMetrics.PowerMeanW
            GpuTempC = $GpuMetrics.TempMaxC
            GpuUtilPct = $GpuMetrics.UtilMaxPct
            GpuUtilMeanPct = $GpuMetrics.UtilMeanPct
            GpuSamples = $GpuMetrics.Samples
        }
    }
    
    Write-Host ""
}

# ============================================
# Generate Summary
# ============================================
Write-Host "=== SUMMARY ==="
Write-Host "GPU: $gpuName ($gpuVramGb GB)"
Write-Host ""

$SummaryHeaders = "mode,model,size_gb,pp_tok_s,pp_stddev,tg_tok_s,tg_stddev,gpu_mem_mb,gpu_power_max_w,gpu_power_mean_w,gpu_samples"
$SummaryHeaders | Out-File -FilePath $SummaryFile -Encoding UTF8

$GroupedResults = $AllResults | Group-Object -Property Model

foreach ($group in $GroupedResults) {
    $pp = $group.Group | Where-Object { $_.Test -like "pp*" } | Select-Object -First 1
    $tg = $group.Group | Where-Object { $_.Test -like "tg*" } | Select-Object -First 1
    
    if ($pp -and $tg) {
        Write-Host "$($group.Name):"
        Write-Host "  Prompt:   $($pp.TokPerSec) ± $($pp.StdDev) tok/s"
        Write-Host "  Generate: $($tg.TokPerSec) ± $($tg.StdDev) tok/s"
        Write-Host "  VRAM:     $($tg.GpuMemMb) MB | Power: $($tg.GpuPowerMeanW)W avg / $($tg.GpuPowerW)W max | Samples: $($tg.GpuSamples)"
        Write-Host ""
        
        $SummaryLine = "$Mode,$($group.Name),$($pp.SizeGb),$($pp.TokPerSec),$($pp.StdDev),$($tg.TokPerSec),$($tg.StdDev),$($tg.GpuMemMb),$($tg.GpuPowerW),$($tg.GpuPowerMeanW),$($tg.GpuSamples)"
        $SummaryLine | Out-File -FilePath $SummaryFile -Append -Encoding UTF8
    }
}

# Append completion to run summary
@"

=== RUN COMPLETE: $(Get-Date -Format "o") ===
Results: $CsvFile
Summary: $SummaryFile
"@ | Out-File -FilePath $RunSummaryFile -Append -Encoding UTF8

Write-Host "=== RUN COMPLETE ==="
Write-Host "Results: $CsvFile"
Write-Host "Summary: $SummaryFile"