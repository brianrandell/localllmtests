# Get-DisplayConfig.ps1 v2 - Maps monitors to GPUs via PnP parent relationships

function Get-ConnectionName {
    param([int]$Value)
    switch ($Value) {
        0  { "VGA" }
        1  { "S-Video" }
        2  { "Composite" }
        3  { "Component" }
        4  { "DVI" }
        5  { "HDMI" }
        6  { "LVDS" }
        8  { "D-Terminal" }
        9  { "SDI" }
        10 { "DisplayPort" }
        11 { "DisplayPort (Embedded/eDP)" }
        12 { "UDI (External)" }
        13 { "UDI (Embedded)" }
        14 { "SDTV Dongle" }
        15 { "Miracast" }
        16 { "Wired Indirect" }
        17 { "Virtual Indirect" }
        80 { "Internal" }
        -1 { "Other" }
        -2 { "Uninitialized" }
        default { "Unknown ($Value)" }
    }
}

Write-Host "`n=== Display Configuration ===" -ForegroundColor Cyan
Write-Host ""

# Get all active monitors as PnP devices
$monitors = Get-PnpDevice -Class Monitor -Status OK -ErrorAction SilentlyContinue

# Pull WMI data once
$wmiIds   = Get-CimInstance -Namespace root\wmi -ClassName WmiMonitorID -ErrorAction SilentlyContinue
$wmiConns = Get-CimInstance -Namespace root\wmi -ClassName WmiMonitorConnectionParams -ErrorAction SilentlyContinue

# Build monitor info with parent-GPU resolution
$monitorInfo = foreach ($mon in $monitors) {
    # Parent of a monitor PnP device is the display adapter (GPU)
    $parentId = (Get-PnpDeviceProperty -InstanceId $mon.InstanceId `
        -KeyName 'DEVPKEY_Device_Parent' -ErrorAction SilentlyContinue).Data
    $parentDev = if ($parentId) { Get-PnpDevice -InstanceId $parentId -ErrorAction SilentlyContinue }
    $gpuName = if ($parentDev) { $parentDev.FriendlyName } else { "Unknown GPU" }

    # WMI InstanceName = PnP InstanceId + "_0" suffix
    $wmiId   = $wmiIds   | Where-Object { $_.InstanceName -like "$($mon.InstanceId)*" } | Select-Object -First 1
    $wmiConn = $wmiConns | Where-Object { $_.InstanceName -like "$($mon.InstanceId)*" } | Select-Object -First 1

    $friendlyName = if ($wmiId -and $wmiId.UserFriendlyName) {
        -join ($wmiId.UserFriendlyName | Where-Object { $_ -ne 0 } | ForEach-Object { [char]$_ })
    } else { $mon.FriendlyName }

    $connection = if ($wmiConn) { Get-ConnectionName $wmiConn.VideoOutputTechnology } else { "Unknown" }

    [PSCustomObject]@{
        Monitor    = $friendlyName
        Connection = $connection
        GPU        = $gpuName
        ParentId   = $parentId
    }
}

# Group by GPU
$grouped = $monitorInfo | Group-Object -Property GPU

foreach ($group in $grouped) {
    Write-Host "GPU: $($group.Name)" -ForegroundColor Yellow
    $parentId = $group.Group[0].ParentId
    if ($parentId) {
        Write-Host "Adapter: $parentId" -ForegroundColor DarkGray
    }
    foreach ($m in $group.Group) {
        Write-Host "  • " -NoNewline
        Write-Host "$($m.Monitor)" -ForegroundColor White -NoNewline
        Write-Host " ($($m.Connection))" -ForegroundColor Gray
    }
    Write-Host ""
}

# nvidia-smi summary (if present)
$nvsmi = nvidia-smi --query-gpu=index,name,display_active --format=csv 2>$null
if ($LASTEXITCODE -eq 0 -and $nvsmi) {
    Write-Host "=== nvidia-smi Status ===" -ForegroundColor Cyan
    $nvsmi
}