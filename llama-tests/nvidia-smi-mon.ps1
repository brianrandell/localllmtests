<#
.SYNOPSIS
    Logs nvidia-smi GPU metrics to CSV for external benchmark monitoring.

.DESCRIPTION
    Continuously logs GPU metrics (VRAM, power, temp, clocks, utilization) 
    until stopped with Ctrl+C or duration expires. Useful for monitoring 
    during 3DMark, games, or other GPU benchmarks.

.PARAMETER Gpu
    GPU index to monitor (default: 0)

.PARAMETER IntervalMs
    Polling interval in milliseconds (default: 250)

.PARAMETER Duration
    Optional duration in seconds. If not specified, runs until Ctrl+C.

.PARAMETER OutputDir
    Output directory for log files (default: .\logs\nvidia-smi)

.PARAMETER Label
    Optional label for the log file (e.g., "3dmark-timespy-4k")

.EXAMPLE
    .\log-nvidia-smi.ps1 -Label "3dmark-timespy-1080p"
    .\log-nvidia-smi.ps1 -Gpu 1 -Label "3dmark-4k" -Duration 300
    .\log-nvidia-smi.ps1 -IntervalMs 500 -Label "firestrike"
#>

param(
    [int]$Gpu = 0,
    [int]$IntervalMs = 250,
    [int]$Duration = 0,
    [string]$OutputDir = ".\logs\nvidia-smi",
    [string]$Label = ""
)

# Create output directory
if (-not (Test-Path $OutputDir)) {
    New-Item -ItemType Directory -Path $OutputDir -Force | Out-Null
}

# Get GPU info
$gpuInfo = nvidia-smi -i $Gpu --query-gpu=name,memory.total --format=csv,noheader 2>&1
if ($LASTEXITCODE -ne 0) {
    Write-Error "nvidia-smi failed. Is GPU $Gpu available?"
    exit 1
}

$gpuName = ($gpuInfo -split ",")[0].Trim()
$gpuVram = ($gpuInfo -split ",")[1].Trim()

# Generate filename
$timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
$labelPart = if ($Label) { "-$Label" } else { "" }
$logFile = Join-Path $OutputDir "nvidia-smi-gpu$Gpu$labelPart-$timestamp.csv"

# Write header
"timestamp,gpu_name,mem_used_mb,mem_total_mb,mem_pct,gpu_util_pct,mem_util_pct,gpu_clock_mhz,mem_clock_mhz,power_w,power_limit_w,temp_c,fan_pct" | Out-File -FilePath $logFile -Encoding UTF8

Write-Host "======================================" -ForegroundColor Cyan
Write-Host "  NVIDIA GPU Monitor" -ForegroundColor Cyan
Write-Host "======================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "GPU $Gpu : $gpuName ($gpuVram)" -ForegroundColor Green
Write-Host "Interval: ${IntervalMs}ms"
Write-Host "Output: $logFile"
if ($Duration -gt 0) {
    Write-Host "Duration: ${Duration}s"
} else {
    Write-Host "Duration: Until Ctrl+C"
}
Write-Host ""
Write-Host "Logging started at $(Get-Date -Format 'HH:mm:ss')" -ForegroundColor Yellow
Write-Host "Press Ctrl+C to stop..." -ForegroundColor DarkGray
Write-Host ""

# Stats tracking
$samples = 0
$maxPower = 0
$maxTemp = 0
$maxMemUsed = 0
$maxGpuUtil = 0
$powerSum = 0
$tempSum = 0

$startTime = Get-Date
$endTime = if ($Duration -gt 0) { $startTime.AddSeconds($Duration) } else { $null }

try {
    while ($true) {
        # Check duration
        if ($endTime -and (Get-Date) -ge $endTime) {
            Write-Host "`nDuration reached." -ForegroundColor Yellow
            break
        }

        $ts = Get-Date -Format "o"
        
        # Query nvidia-smi
        $smi = nvidia-smi -i $Gpu --query-gpu=memory.used,memory.total,utilization.gpu,utilization.memory,clocks.current.graphics,clocks.current.memory,power.draw,power.limit,temperature.gpu,fan.speed --format=csv,noheader,nounits 2>&1
        
        if ($LASTEXITCODE -eq 0) {
            $parts = $smi -split ","
            if ($parts.Count -ge 10) {
                $memUsed = [double]$parts[0].Trim()
                $memTotal = [double]$parts[1].Trim()
                $memPct = [math]::Round(($memUsed / $memTotal) * 100, 1)
                $gpuUtil = [double]$parts[2].Trim()
                $memUtil = [double]$parts[3].Trim()
                $gpuClock = $parts[4].Trim()
                $memClock = $parts[5].Trim()
                $power = [double]$parts[6].Trim()
                $powerLimit = $parts[7].Trim()
                $temp = [double]$parts[8].Trim()
                $fan = $parts[9].Trim()
                
                # Update stats
                $samples++
                $powerSum += $power
                $tempSum += $temp
                if ($power -gt $maxPower) { $maxPower = $power }
                if ($temp -gt $maxTemp) { $maxTemp = $temp }
                if ($memUsed -gt $maxMemUsed) { $maxMemUsed = $memUsed }
                if ($gpuUtil -gt $maxGpuUtil) { $maxGpuUtil = $gpuUtil }
                
                # Write to log
                "$ts,$gpuName,$memUsed,$memTotal,$memPct,$gpuUtil,$memUtil,$gpuClock,$memClock,$power,$powerLimit,$temp,$fan" | Out-File -FilePath $logFile -Append -Encoding UTF8
                
                # Live display (update every ~1 second)
                if ($samples % [math]::Max(1, [math]::Round(1000 / $IntervalMs)) -eq 0) {
                    $elapsed = [math]::Round(((Get-Date) - $startTime).TotalSeconds, 0)
                    Write-Host "`r  [$elapsed`s] GPU: $gpuUtil% | Mem: $([math]::Round($memUsed/1024,1))/$([math]::Round($memTotal/1024,1)) GB ($memPct%) | Power: ${power}W | Temp: ${temp}C | Samples: $samples    " -NoNewline
                }
            }
        }
        
        Start-Sleep -Milliseconds $IntervalMs
    }
}
finally {
    # Summary
    $elapsed = [math]::Round(((Get-Date) - $startTime).TotalSeconds, 1)
    $avgPower = if ($samples -gt 0) { [math]::Round($powerSum / $samples, 1) } else { 0 }
    $avgTemp = if ($samples -gt 0) { [math]::Round($tempSum / $samples, 1) } else { 0 }
    
    Write-Host ""
    Write-Host ""
    Write-Host "======================================" -ForegroundColor Cyan
    Write-Host "  Logging Complete" -ForegroundColor Cyan
    Write-Host "======================================" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "GPU: $gpuName" -ForegroundColor White
    Write-Host "Duration: ${elapsed}s | Samples: $samples"
    Write-Host ""
    Write-Host "Peak Values:" -ForegroundColor Yellow
    Write-Host "  VRAM:  $([math]::Round($maxMemUsed/1024, 2)) GB"
    Write-Host "  Power: ${maxPower}W (avg: ${avgPower}W)"
    Write-Host "  Temp:  ${maxTemp}C (avg: ${avgTemp}C)"
    Write-Host "  GPU:   ${maxGpuUtil}%"
    Write-Host ""
    Write-Host "Log saved: $logFile" -ForegroundColor Green
}