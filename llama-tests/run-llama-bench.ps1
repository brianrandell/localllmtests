<#
.SYNOPSIS
    Runs llama-bench.exe on multiple GGUF models with nvidia-smi monitoring.
    Auto-detects GPU and selects appropriate models based on VRAM.

.DESCRIPTION
    Hardware comparison benchmark using llama-bench.exe.
    Captures GPU metrics (VRAM, power, temp, utilization) during each run.
    
    GPU Detection:
    - 96GB+ (RTX PRO 6000): Full suite including 70B-122B models
    - 32GB+ (RTX 5090): Medium models including Q6 quants
    - 24GB (RTX 3090/4090): Base models (Q4_K_M only)
    - 11GB (Legacy): Small models only

.NOTES
    Date: 2026-02-28 (Major v2 - updated models)
    Total Download Size: ~800 GB (all models)

.PARAMETER Mode
    Test mode identifier (e.g., "6000-pcie", "5090-pcie", "4090-pcie", "3090-pcie")

.PARAMETER Gpu
    GPU index to use (0, 1, etc.). Use -ListGpus to see available GPUs.
    If not specified, uses GPU 0.

.PARAMETER ListGpus
    List available GPUs and exit.

.PARAMETER Repeats
    Number of llama-bench repetitions per model (default: 10)

.PARAMETER ListModels
    List all models that would be run for the detected GPU and exit.

.EXAMPLE
    .\run-llama-bench.ps1 -ListGpus
    .\run-llama-bench.ps1 -Mode "6000-pcie" -Gpu 0
    .\run-llama-bench.ps1 -Mode "5090-pcie" -Gpu 1 -ListModels
    .\run-llama-bench.ps1 -Mode "4090-pcie" -Repeats 5
#>

param(
    [Parameter(Mandatory=$false)]
    [string]$Mode,
    
    [int]$Gpu = -1,
    
    [switch]$ListGpus,
    
    [switch]$ListModels,
    
    [int]$Repeats = 10,
    
    [int]$PromptTokens = 2048,
    
    [int]$GenTokens = 512,
    
    [int]$SmiIntervalMs = 250
)

# Paths
$LlamaBenchExe = ".\llama-cpp\llama-bench.exe"
$GgufDir = ".\gguf"

# ============================================
# Model Definitions
# ============================================
# Format: @{ Path = "relative/path.gguf"; Desc = "Description"; SizeGB = approx }
# For split files, use the -00001-of-XXXXX.gguf part

$Models11GB = @(
    @{ Path = "Meta-Llama-3.1-8B-Instruct-Q4_K_M.gguf"; Desc = "Llama 3.1 8B Q4"; SizeGB = 4.6 },
    @{ Path = "Qwen2.5-Coder-7B-Instruct-Q4_K_M.gguf"; Desc = "Qwen 2.5 Coder 7B Q4"; SizeGB = 4.4 },
    @{ Path = "Ministral-8B-Instruct-2410-Q4_K_M.gguf"; Desc = "Ministral 8B Q4"; SizeGB = 4.6 }
)

$Models24GB = @(
    @{ Path = "phi-4-Q4_K_M.gguf"; Desc = "Phi-4 14B Q4"; SizeGB = 8.4 },
    @{ Path = "Qwen2.5-Coder-32B-Instruct-Q4_K_M.gguf"; Desc = "Qwen 2.5 Coder 32B Q4"; SizeGB = 18.5 },
    @{ Path = "Nemotron-3-Nano-30B-A3B-UD-Q4_K_XL.gguf"; Desc = "Nemotron-3-Nano 30B MoE Q4"; SizeGB = 21.3 },
    @{ Path = "Qwen3.5-35B-A3B-UD-Q4_K_XL.gguf"; Desc = "Qwen 3.5 35B MoE Q4 [NEW]"; SizeGB = 19.2 }
)

$Models32GB = @(
    @{ Path = "Qwen2.5-Coder-32B-Instruct-Q6_K.gguf"; Desc = "Qwen 2.5 Coder 32B Q6"; SizeGB = 25.0 },
    @{ Path = "Qwen3.5-27B-Q6_K.gguf"; Desc = "Qwen 3.5 27B Dense Q6 [NEW]"; SizeGB = 20.9 }
)

$Models96GB = @(
    @{ Path = "DeepSeek-R1-Distill-Llama-70B-Q4_K_M.gguf"; Desc = "DeepSeek-R1 70B Q4"; SizeGB = 39.6 },
    @{ Path = "Qwen2.5-72B-Instruct-Q4_K_M.gguf"; Desc = "Qwen 2.5 72B Q4"; SizeGB = 44.2 },
    @{ Path = "gpt-oss-20b-mxfp4.gguf"; Desc = "GPT-OSS 20B MXFP4"; SizeGB = 11.3 },
    # Split files - point to first part
    @{ Path = "Qwen2.5-72B-Instruct-Q8_0\Qwen2.5-72B-Instruct-Q8_0-00001-of-00002.gguf"; Desc = "Qwen 2.5 72B Q8 [Split]"; SizeGB = 72.0 },
    @{ Path = "Meta-Llama-3.1-70B-Instruct-Q6_K\Meta-Llama-3.1-70B-Instruct-Q6_K-00001-of-00002.gguf"; Desc = "Llama 3.1 70B Q6 [Split]"; SizeGB = 53.9 },
    @{ Path = "Meta-Llama-3.1-70B-Instruct-Q8_0\Meta-Llama-3.1-70B-Instruct-Q8_0-00001-of-00002.gguf"; Desc = "Llama 3.1 70B Q8 [Split]"; SizeGB = 69.8 },
    @{ Path = "c4ai-command-r-plus-08-2024-Q4_K_M\c4ai-command-r-plus-08-2024-Q4_K_M-00001-of-00002.gguf"; Desc = "Command-R+ 104B Q4 [Split]"; SizeGB = 58.5 },
    @{ Path = "c4ai-command-r-plus-08-2024-Q6_K\c4ai-command-r-plus-08-2024-Q6_K-00001-of-00003.gguf"; Desc = "Command-R+ 104B Q6 [Split]"; SizeGB = 79.3 },
    @{ Path = "Qwen3.5-122B\Q4_K_M\Qwen3.5-122B-A10B-Q4_K_M-00001-of-00003.gguf"; Desc = "Qwen 3.5 122B MoE Q4 [NEW Split]"; SizeGB = 69.2 },
    @{ Path = "gpt-oss-120b\gpt-oss-120b-mxfp4-00001-of-00003.gguf"; Desc = "GPT-OSS 120B MoE MXFP4 [Split]"; SizeGB = 59.0 }
)

# ============================================
# List GPUs Mode
# ============================================
if ($ListGpus) {
    Write-Host "Available GPUs:" -ForegroundColor Cyan
    $gpuList = nvidia-smi --query-gpu=index,name,memory.total --format=csv,noheader,nounits 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-Error "nvidia-smi failed. Is an NVIDIA GPU present?"
        exit 1
    }
    
    $gpuList -split "`n" | ForEach-Object {
        $parts = $_ -split ","
        if ($parts.Count -ge 3) {
            $idx = $parts[0].Trim()
            $name = $parts[1].Trim()
            $vram = [math]::Round([int]$parts[2].Trim() / 1024, 1)
            Write-Host "  GPU ${idx}: $name ($vram GB)" -ForegroundColor White
        }
    }
    Write-Host ""
    Write-Host "Usage: .\run-llama-bench.ps1 -Mode <name> -Gpu <index>" -ForegroundColor Yellow
    exit 0
}

# ============================================
# Validate Mode Parameter
# ============================================
if (-not $Mode -and -not $ListModels) {
    Write-Error "Mode parameter is required. Use -ListGpus to see available GPUs."
    Write-Host "Example: .\run-llama-bench.ps1 -Mode '5090-pcie' -Gpu 1" -ForegroundColor Yellow
    exit 1
}

# ============================================
# GPU Detection
# ============================================
Write-Host "Detecting GPU(s)..." -ForegroundColor Cyan

# Get list of all GPUs
$gpuList = nvidia-smi --query-gpu=index,name,memory.total --format=csv,noheader,nounits 2>&1
if ($LASTEXITCODE -ne 0) {
    Write-Error "nvidia-smi failed. Is an NVIDIA GPU present?"
    exit 1
}

$gpuArray = @()
$gpuList -split "`n" | ForEach-Object {
    $parts = $_ -split ","
    if ($parts.Count -ge 3) {
        $gpuArray += @{
            Index = [int]$parts[0].Trim()
            Name = $parts[1].Trim()
            VramMb = [int]$parts[2].Trim()
        }
    }
}

# Show available GPUs
if ($gpuArray.Count -gt 1) {
    Write-Host "  Found $($gpuArray.Count) GPUs:" -ForegroundColor Yellow
    foreach ($g in $gpuArray) {
        $vramGb = [math]::Round($g.VramMb / 1024, 1)
        Write-Host "    GPU $($g.Index): $($g.Name) ($vramGb GB)" -ForegroundColor White
    }
}

# Select GPU
if ($Gpu -eq -1) {
    if ($gpuArray.Count -gt 1) {
        Write-Host ""
        Write-Host "  Multiple GPUs detected. Use -Gpu <index> to select." -ForegroundColor Yellow
        Write-Host "  Defaulting to GPU 0." -ForegroundColor Yellow
    }
    $Gpu = 0
}

if ($Gpu -ge $gpuArray.Count) {
    Write-Error "GPU $Gpu not found. Available GPUs: 0-$($gpuArray.Count - 1)"
    exit 1
}

$selectedGpu = $gpuArray | Where-Object { $_.Index -eq $Gpu }
$gpuName = $selectedGpu.Name
$gpuVramMb = $selectedGpu.VramMb
$gpuVramGb = [math]::Round($gpuVramMb / 1024, 1)

Write-Host ""
Write-Host "  Selected GPU $Gpu : $gpuName" -ForegroundColor Green
Write-Host "  VRAM: $gpuVramGb GB ($gpuVramMb MB)"

# Set CUDA_VISIBLE_DEVICES to use only the selected GPU
$env:CUDA_VISIBLE_DEVICES = "$Gpu"
Write-Host "  CUDA_VISIBLE_DEVICES=$Gpu" -ForegroundColor DarkGray

# ============================================
# Model Selection Based on VRAM
# ============================================

# Build model list based on VRAM
$SelectedModels = @()
$ProfileName = ""

if ($gpuVramMb -ge 90000) {
    # 96GB+ card (RTX PRO 6000 Blackwell, etc.)
    $SelectedModels = $Models11GB + $Models24GB + $Models32GB + $Models96GB
    $ProfileName = "96GB+ (Full Suite)"
} elseif ($gpuVramMb -ge 30000) {
    # 32GB+ card (RTX 5090, etc.)
    $SelectedModels = $Models11GB + $Models24GB + $Models32GB
    $ProfileName = "32GB+ (Medium)"
} elseif ($gpuVramMb -ge 20000) {
    # 24GB card (RTX 3090, 4090, etc.)
    $SelectedModels = $Models11GB + $Models24GB
    $ProfileName = "24GB (Consumer)"
} else {
    # 11GB or less
    $SelectedModels = $Models11GB
    $ProfileName = "11GB (Legacy)"
}

Write-Host "  Profile: $ProfileName ($($SelectedModels.Count) models)" -ForegroundColor Magenta
Write-Host ""

# ============================================
# List Models Mode
# ============================================
if ($ListModels) {
    Write-Host "Models for $ProfileName profile:" -ForegroundColor Cyan
    Write-Host ""
    $idx = 0
    foreach ($model in $SelectedModels) {
        $idx++
        $modelPath = Join-Path $GgufDir $model.Path
        $exists = if (Test-Path $modelPath) { "[OK]" } else { "[MISSING]" }
        $color = if (Test-Path $modelPath) { "Green" } else { "Red" }
        Write-Host ("  {0,2}. {1,-45} {2,7} GB  {3}" -f $idx, $model.Desc, $model.SizeGB, $exists) -ForegroundColor $color
    }
    Write-Host ""
    exit 0
}

# ============================================
# Verify Models Exist
# ============================================
$MissingModels = @()
foreach ($model in $SelectedModels) {
    $ModelPath = Join-Path $GgufDir $model.Path
    if (-not (Test-Path $ModelPath)) {
        $MissingModels += $model
    }
}

if ($MissingModels.Count -gt 0) {
    Write-Host "Missing model files:" -ForegroundColor Red
    foreach ($m in $MissingModels) {
        Write-Host "  - $($m.Desc): $($m.Path)" -ForegroundColor Red
    }
    Write-Host ""
    Write-Host "Run download script to get missing models:" -ForegroundColor Yellow
    Write-Host "  .\download-all-models-v3.ps1" -ForegroundColor Gray
    Write-Host ""
    Write-Host "Or continue with available models? (Ctrl+C to abort)" -ForegroundColor Yellow
    
    # Filter to only existing models
    $SelectedModels = $SelectedModels | Where-Object { 
        $ModelPath = Join-Path $GgufDir $_.Path
        Test-Path $ModelPath 
    }
    
    if ($SelectedModels.Count -eq 0) {
        Write-Error "No models available. Exiting."
        exit 1
    }
    
    Write-Host "Continuing with $($SelectedModels.Count) available models..." -ForegroundColor Yellow
    Start-Sleep -Seconds 3
}

# ============================================
# Setup Output Directories
# ============================================
$Timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
$LogDir = ".\logs\$Mode-$Timestamp"
New-Item -ItemType Directory -Path $LogDir -Force | Out-Null

$CsvFile = Join-Path $LogDir "results.csv"
$SummaryFile = Join-Path $LogDir "summary.csv"
$RunSummaryFile = Join-Path $LogDir "run-summary.txt"

# CSV Header
"mode,model,size_gb,test,tokens,repeats,tok_per_sec,stddev,gpu_mem_mb,gpu_power_max_w,gpu_power_mean_w,gpu_temp_c,gpu_util_max_pct,gpu_util_mean_pct,gpu_samples,timestamp" | Out-File -FilePath $CsvFile -Encoding UTF8

# Get nvidia-smi info
$NvidiaSmiInfo = nvidia-smi -i $Gpu --query-gpu=name,memory.total,driver_version,vbios_version --format=csv 2>&1 | Out-String

@"
==================
llama-bench Run
==================
Mode: $Mode
GPU: $Gpu - $gpuName ($gpuVramGb GB)
Profile: $ProfileName
Timestamp: $Timestamp
Repeats: $Repeats
SMI Interval: ${SmiIntervalMs}ms
Models: $($SelectedModels.Count)

$($SelectedModels | ForEach-Object { "  - $($_.Desc)" } | Out-String)

nvidia-smi:
$NvidiaSmiInfo
==================
"@ | Out-File -FilePath $RunSummaryFile -Encoding UTF8

Write-Host "llama-bench Hardware Comparison"
Write-Host "================================"
Write-Host "Mode: $Mode"
Write-Host "GPU $Gpu : $gpuName ($gpuVramGb GB)"
Write-Host "Profile: $ProfileName"
Write-Host "Models: $($SelectedModels.Count)"
Write-Host "Repeats: $Repeats"
Write-Host "SMI Interval: ${SmiIntervalMs}ms"
Write-Host "Output: $LogDir"
Write-Host ""

# ============================================
# GPU Monitor Functions
# ============================================
function Start-GpuMonitor {
    param([string]$LogFile, [int]$IntervalMs = 500, [int]$GpuIndex = 0)
    
    $logDir = Split-Path -Parent $LogFile
    if (-not (Test-Path $logDir)) { New-Item -ItemType Directory -Path $logDir -Force | Out-Null }
    
    $scriptPath = Join-Path ([System.IO.Path]::GetTempPath()) "nvidia-smi-logger-$([Guid]::NewGuid().ToString('N').Substring(0,8)).ps1"
    
    $scriptContent = @"
`$ErrorActionPreference = 'SilentlyContinue'
`$outFile = '$($LogFile -replace "'", "''")'
while (`$true) {
    `$ts = Get-Date -Format o
    `$smi = nvidia-smi -i $GpuIndex --query-gpu=memory.used,memory.total,utilization.gpu,power.draw,temperature.gpu --format=csv,noheader,nounits 2>&1
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

foreach ($model in $SelectedModels) {
    $ModelIndex++
    $ModelPath = Join-Path $GgufDir $model.Path
    
    $ModelName = $model.Desc
    $ModelFileName = [System.IO.Path]::GetFileNameWithoutExtension($model.Path)
    Write-Host "[$ModelIndex/$($SelectedModels.Count)] $ModelName"
    Write-Host "  File: $($model.Path)" -ForegroundColor DarkGray
    
    $ModelLogDir = Join-Path $LogDir ($ModelFileName -replace "[^\w\-]", "_")
    New-Item -ItemType Directory -Path $ModelLogDir -Force | Out-Null
    
    $GpuLogFile = Join-Path $ModelLogDir "nvidia-smi.csv"
    "timestamp,mem_used_mb,mem_total_mb,util_pct,power_w,temp_c" | Out-File -FilePath $GpuLogFile -Encoding UTF8
    $GpuProc = Start-GpuMonitor -LogFile $GpuLogFile -IntervalMs $SmiIntervalMs -GpuIndex $Gpu
    
    Start-Sleep -Milliseconds 500
    
    Write-Host "  Running llama-bench (pp$PromptTokens, tg$GenTokens, r$Repeats)..."
    $BenchOutput = & $LlamaBenchExe -m $ModelPath -p $PromptTokens -n $GenTokens -r $Repeats 2>&1 | Out-String
    
    if ($GpuProc -and -not $GpuProc.HasExited) {
        Stop-Process -Id $GpuProc.Id -Force -ErrorAction SilentlyContinue
    }
    
    $BenchOutput | Out-File -FilePath (Join-Path $ModelLogDir "llama-bench-output.txt") -Encoding UTF8
    
    $ParsedResults = Parse-LlamaBenchOutput -Output $BenchOutput
    $GpuMetrics = Get-GpuMetrics -LogFile $GpuLogFile
    $FileSizeGb = [math]::Round((Get-Item $ModelPath).Length / 1GB, 2)
    
    # For split files, calculate total size
    $parentDir = Split-Path $ModelPath -Parent
    $baseName = [System.IO.Path]::GetFileName($ModelPath) -replace "-00001-of-\d+\.gguf$", ""
    if ($model.Path -match "-00001-of-\d+\.gguf$") {
        $allParts = Get-ChildItem -Path $parentDir -Filter "$baseName*.gguf" -ErrorAction SilentlyContinue
        $FileSizeGb = [math]::Round(($allParts | Measure-Object -Property Length -Sum).Sum / 1GB, 2)
    }
    
    foreach ($result in $ParsedResults) {
        Write-Host "    $($result.Test): $($result.TokPerSec) ± $($result.StdDev) tok/s"
        
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
Write-Host "GPU $Gpu : $gpuName ($gpuVramGb GB)"
Write-Host "Profile: $ProfileName"
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

@"

=== RUN COMPLETE: $(Get-Date -Format "o") ===
Results: $CsvFile
Summary: $SummaryFile
"@ | Out-File -FilePath $RunSummaryFile -Append -Encoding UTF8

Write-Host "=== RUN COMPLETE ==="
Write-Host "Results: $CsvFile"
Write-Host "Summary: $SummaryFile"