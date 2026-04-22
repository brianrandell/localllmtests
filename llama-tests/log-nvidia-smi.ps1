# log-nvidia-smi.ps1
# Logs GPU metrics at 250ms intervals to CSV
# Usage: .\log-nvidia-smi.ps1 -Label "3dmark-timespy-6000-pcie-x16" [-GpuIndex 0] [-IntervalMs 250]

param(
    [Parameter(Mandatory=$true)]
    [string]$Label,

    [int]$GpuIndex = 0,

    [int]$IntervalMs = 250
)

$timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
$logDir = ".\logs\nvidia-smi"
if (-not (Test-Path $logDir)) {
    New-Item -ItemType Directory -Path $logDir | Out-Null
}

$outputFile = "$logDir\nvidia-smi-gpu$GpuIndex-$Label-$timestamp.csv"

$queryFields = @(
    "timestamp",
    "name",
    "index",
    "clocks.current.graphics",
    "clocks.current.memory",
    "power.draw",
    "power.limit",
    "utilization.gpu",
    "utilization.memory",
    "memory.used",
    "memory.total",
    "temperature.gpu",
    "fan.speed"
) -join ","

Write-Host "nvidia-smi logger started" -ForegroundColor Cyan
Write-Host "GPU:      $GpuIndex" -ForegroundColor Cyan
Write-Host "Label:    $Label" -ForegroundColor Cyan
Write-Host "Interval: $($IntervalMs)ms" -ForegroundColor Cyan
Write-Host "Output:   $outputFile" -ForegroundColor Cyan
Write-Host "Press Ctrl+C to stop." -ForegroundColor Yellow
Write-Host ""

# Write header
"timestamp,name,index,clock_gpu_mhz,clock_mem_mhz,power_draw_w,power_limit_w,util_gpu_pct,util_mem_pct,vram_used_mb,vram_total_mb,temp_c,fan_pct" |
    Out-File -FilePath $outputFile -Encoding utf8

$sampleCount = 0

try {
    while ($true) {
        $raw = & nvidia-smi `
            --query-gpu=$queryFields `
            --format=csv,noheader,nounits `
            --id=$GpuIndex 2>$null

        if ($raw) {
            $raw.Trim() | Out-File -FilePath $outputFile -Append -Encoding utf8
            $sampleCount++

            # Show live summary every 10 samples (~2.5s)
            if ($sampleCount % 10 -eq 0) {
                $fields = $raw.Trim() -split ",\s*"
                $power  = if ($fields.Count -gt 5) { "$($fields[5].Trim())W" } else { "?" }
                $util   = if ($fields.Count -gt 7) { "$($fields[7].Trim())%" } else { "?" }
                $temp   = if ($fields.Count -gt 11) { "$($fields[11].Trim())°C" } else { "?" }
                $vram   = if ($fields.Count -gt 9) { "$($fields[9].Trim())MB" } else { "?" }
                Write-Host "  [sample $sampleCount] Power: $power  Util: $util  Temp: $temp  VRAM: $vram"
            }
        }

        Start-Sleep -Milliseconds $IntervalMs
    }
}
finally {
    Write-Host ""
    Write-Host "Logger stopped. $sampleCount samples written to:" -ForegroundColor Green
    Write-Host "  $outputFile" -ForegroundColor Green
}