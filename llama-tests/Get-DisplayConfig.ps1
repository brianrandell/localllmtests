# Get-DisplayConfig.ps1 - Maps monitors to GPUs

# Get all display adapters
$adapters = Get-PnpDevice -Class Display -Status OK | Select-Object FriendlyName, InstanceId

# Get all monitors with connection info
$monitors = Get-CimInstance -Namespace root\wmi -ClassName WmiMonitorConnectionParams | ForEach-Object {
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
            0 {"VGA"}; 2 {"S-Video"}; 3 {"Composite"}; 4 {"Component"}
            5 {"DisplayPort"}; 6 {"DisplayPort"}; 8 {"DVI"}; 9 {"DVI"}
            10 {"HDMI"}; 11 {"Internal/eDP"}; 12 {"SDI"}; 14 {"DisplayPort"}
            default {"Unknown ($($_.VideoOutputTechnology))"}
        }
    }
}

# Build adapter ID to GPU name mapping by checking which adapters have displays
$adapterMap = @{}
foreach ($adapter in $adapters) {
    # Check nvidia-smi for display status
    $gpuIdx = $null
    if ($adapter.FriendlyName -like "*NVIDIA*" -or $adapter.FriendlyName -like "*RTX*" -or $adapter.FriendlyName -like "*GeForce*") {
        # It's an NVIDIA GPU - we'll map by checking display_active
    } elseif ($adapter.FriendlyName -like "*Intel*") {
        # Intel iGPU
    }
}

# Group monitors by adapter ID and show with GPU names
$grouped = $monitors | Group-Object AdapterID

Write-Host "`n=== Display Configuration ===" -ForegroundColor Cyan
Write-Host ""

foreach ($group in $grouped) {
    # Determine GPU name based on adapter count and nvidia-smi
    $gpuName = "Unknown GPU"
    
    # Check if this is Intel (usually has fewer monitors or specific ID pattern)
    $monitorCount = $group.Count
    $firstMonitor = $group.Group[0]
    
    # Simple heuristic: query nvidia-smi for display status
    $nvidiaSmi = nvidia-smi --query-gpu=index,name,display_active --format=csv,noheader 2>$null
    if ($nvidiaSmi) {
        $gpus = $nvidiaSmi | ForEach-Object {
            $parts = $_ -split ', '
            [PSCustomObject]@{
                Index = $parts[0].Trim()
                Name = $parts[1].Trim()
                DisplayActive = $parts[2].Trim()
            }
        }
        
        # If only one NVIDIA GPU has displays, and this group has multiple monitors, it's likely that GPU
        $activeGpu = $gpus | Where-Object { $_.DisplayActive -eq "Enabled" }
        $inactiveGpu = $gpus | Where-Object { $_.DisplayActive -eq "Disabled" }
        
        if ($group.Count -ge 3 -and $activeGpu) {
            $gpuName = $activeGpu.Name
        } elseif ($group.Count -eq 1 -and $inactiveGpu) {
            # Single monitor on a different adapter = likely Intel
            $gpuName = "Intel Integrated Graphics"
        }
    }
    
    # Also check for Intel adapter
    $intelAdapter = $adapters | Where-Object { $_.FriendlyName -like "*Intel*" }
    if ($intelAdapter -and $group.Count -eq 1) {
        $gpuName = $intelAdapter.FriendlyName
    }
    
    Write-Host "GPU: $gpuName" -ForegroundColor Yellow
    Write-Host "Adapter ID: $($group.Name)" -ForegroundColor DarkGray
    Write-Host ""
    
    $group.Group | ForEach-Object {
        Write-Host "  • $($_.Monitor)" -ForegroundColor White -NoNewline
        Write-Host " ($($_.Connection))" -ForegroundColor Gray
    }
    Write-Host ""
}

# Summary from nvidia-smi
Write-Host "=== nvidia-smi Status ===" -ForegroundColor Cyan
nvidia-smi --query-gpu=index,name,display_active --format=csv