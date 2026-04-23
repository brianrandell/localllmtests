# gwen-health-check.ps1
# Pulls warnings/errors and hardware status from today's logs for review

$startOfDay = (Get-Date).Date
$outputFile = ".\gwen-health-$(Get-Date -Format 'yyyyMMdd-HHmmss').txt"

function Write-Section {
    param([string]$Title)
    "`n" + ("=" * 70) | Out-File -FilePath $outputFile -Append
    "  $Title" | Out-File -FilePath $outputFile -Append
    ("=" * 70) | Out-File -FilePath $outputFile -Append
}

# Header
@"
Gwen Health Check
Generated: $(Get-Date)
Scope: Since $startOfDay
"@ | Out-File -FilePath $outputFile

# === SYSTEM LOG: Errors and Warnings ===
Write-Section "SYSTEM LOG - Errors and Warnings (today)"
Get-WinEvent -FilterHashtable @{
    LogName   = 'System'
    Level     = 1,2,3  # Critical, Error, Warning
    StartTime = $startOfDay
} -ErrorAction SilentlyContinue |
    Select-Object TimeCreated, Id, LevelDisplayName, ProviderName,
        @{N='Message';E={($_.Message -split "`n")[0].Trim()}} |
    Format-Table -AutoSize -Wrap |
    Out-File -FilePath $outputFile -Append -Width 250

# === SYSTEM LOG: Count by provider (spot noisy sources) ===
Write-Section "SYSTEM LOG - Error/Warning count by provider (today)"
Get-WinEvent -FilterHashtable @{
    LogName   = 'System'
    Level     = 1,2,3
    StartTime = $startOfDay
} -ErrorAction SilentlyContinue |
    Group-Object ProviderName, Id, LevelDisplayName |
    Sort-Object Count -Descending |
    Select-Object Count, Name |
    Format-Table -AutoSize |
    Out-File -FilePath $outputFile -Append -Width 250

# === APPLICATION LOG: Errors only ===
Write-Section "APPLICATION LOG - Errors (today)"
Get-WinEvent -FilterHashtable @{
    LogName   = 'Application'
    Level     = 1,2
    StartTime = $startOfDay
} -ErrorAction SilentlyContinue |
    Select-Object TimeCreated, Id, LevelDisplayName, ProviderName,
        @{N='Message';E={($_.Message -split "`n")[0].Trim()}} |
    Format-Table -AutoSize -Wrap |
    Out-File -FilePath $outputFile -Append -Width 250

# === WHEA (hardware errors) ===
Write-Section "WHEA-Logger events (today) - CPU/PCIe/memory hardware errors"
Get-WinEvent -FilterHashtable @{
    LogName   = 'System'
    ProviderName = 'Microsoft-Windows-WHEA-Logger'
    StartTime = $startOfDay
} -ErrorAction SilentlyContinue |
    Select-Object TimeCreated, Id, LevelDisplayName, Message |
    Format-List |
    Out-File -FilePath $outputFile -Append -Width 250

# === KERNEL-PNP driver load failures ===
Write-Section "Kernel-PnP driver load failures (today)"
Get-WinEvent -FilterHashtable @{
    LogName   = 'System'
    ProviderName = 'Microsoft-Windows-Kernel-PnP'
    Level     = 2,3
    StartTime = $startOfDay
} -ErrorAction SilentlyContinue |
    Select-Object TimeCreated, Id, LevelDisplayName,
        @{N='Message';E={($_.Message -split "`n")[0].Trim()}} |
    Format-Table -AutoSize -Wrap |
    Out-File -FilePath $outputFile -Append -Width 250

# === Unexpected shutdowns ===
Write-Section "Unexpected shutdowns / kernel-power 41 (last 7 days)"
Get-WinEvent -FilterHashtable @{
    LogName   = 'System'
    Id        = 41,6008
    StartTime = (Get-Date).AddDays(-7)
} -ErrorAction SilentlyContinue |
    Select-Object TimeCreated, Id, ProviderName, Message |
    Format-List |
    Out-File -FilePath $outputFile -Append -Width 250

# === Physical disk health ===
Write-Section "Physical disks"
Get-PhysicalDisk |
    Select-Object DeviceId, FriendlyName, MediaType, BusType, HealthStatus, OperationalStatus,
        @{N='SizeGB';E={[math]::Round($_.Size/1GB,1)}} |
    Sort-Object DeviceId |
    Format-Table -AutoSize |
    Out-File -FilePath $outputFile -Append -Width 250

Write-Section "Storage reliability counters"
Get-PhysicalDisk | ForEach-Object {
    $disk = $_
    $rel = $disk | Get-StorageReliabilityCounter -ErrorAction SilentlyContinue
    if ($rel) {
        "--- $($disk.FriendlyName) (DeviceId $($disk.DeviceId)) ---" | Out-File -FilePath $outputFile -Append
        $rel | Format-List Temperature, Wear, ReadErrorsTotal, WriteErrorsTotal,
            PowerOnHours, StartStopCycleCount | Out-File -FilePath $outputFile -Append
    }
}

# === Volume health ===
Write-Section "Volumes"
Get-Volume |
    Where-Object { $_.DriveLetter -or $_.FileSystemLabel } |
    Select-Object DriveLetter, FileSystemLabel, FileSystem, HealthStatus, OperationalStatus,
        @{N='SizeGB';E={[math]::Round($_.Size/1GB,1)}},
        @{N='FreeGB';E={[math]::Round($_.SizeRemaining/1GB,1)}} |
    Format-Table -AutoSize |
    Out-File -FilePath $outputFile -Append -Width 250

# === Storage Spaces ===
Write-Section "Storage Spaces / Pools"
Get-StoragePool -ErrorAction SilentlyContinue |
    Where-Object { $_.IsPrimordial -eq $false } |
    Select-Object FriendlyName, HealthStatus, OperationalStatus,
        @{N='SizeGB';E={[math]::Round($_.Size/1GB,1)}},
        @{N='AllocatedGB';E={[math]::Round($_.AllocatedSize/1GB,1)}} |
    Format-Table -AutoSize |
    Out-File -FilePath $outputFile -Append -Width 250

Get-VirtualDisk -ErrorAction SilentlyContinue |
    Select-Object FriendlyName, ResiliencySettingName, HealthStatus, OperationalStatus,
        @{N='SizeGB';E={[math]::Round($_.Size/1GB,1)}} |
    Format-Table -AutoSize |
    Out-File -FilePath $outputFile -Append -Width 250

# === GPU status ===
Write-Section "GPU (nvidia-smi)"
& nvidia-smi --query-gpu=index,name,driver_version,pcie.link.width.current,pcie.link.gen.current,memory.total,temperature.gpu --format=csv 2>&1 |
    Out-File -FilePath $outputFile -Append

# === Device Manager: problem devices ===
Write-Section "Devices with problems (non-zero ConfigManagerErrorCode)"
Get-CimInstance Win32_PnPEntity |
    Where-Object { $_.ConfigManagerErrorCode -ne 0 -and $_.ConfigManagerErrorCode -ne $null } |
    Select-Object Name, ConfigManagerErrorCode, Status, DeviceID |
    Format-Table -AutoSize -Wrap |
    Out-File -FilePath $outputFile -Append -Width 250

# === Recent boot times ===
Write-Section "Recent boots (last 7 days)"
Get-WinEvent -FilterHashtable @{
    LogName   = 'System'
    Id        = 6005,6006,6013
    StartTime = (Get-Date).AddDays(-7)
} -ErrorAction SilentlyContinue |
    Select-Object TimeCreated, Id,
        @{N='Event';E={switch($_.Id){6005{'Event Log started (boot)'};6006{'Event Log stopped (shutdown)'};6013{'Uptime report'}}}} |
    Format-Table -AutoSize |
    Out-File -FilePath $outputFile -Append -Width 250

# === System info ===
Write-Section "System summary"
$cs = Get-CimInstance Win32_ComputerSystem
$os = Get-CimInstance Win32_OperatingSystem
$bios = Get-CimInstance Win32_BIOS
@"
Computer:    $($cs.Name)
Manufacturer:$($cs.Manufacturer)
Model:       $($cs.Model)
OS:          $($os.Caption) $($os.Version)
BIOS:        $($bios.Manufacturer) $($bios.SMBIOSBIOSVersion) ($($bios.ReleaseDate))
Last Boot:   $($os.LastBootUpTime)
Uptime:      $([math]::Round(((Get-Date) - $os.LastBootUpTime).TotalHours,1)) hours
"@ | Out-File -FilePath $outputFile -Append

Write-Host ""
Write-Host "Done. Report written to:" -ForegroundColor Green
Write-Host "  $outputFile" -ForegroundColor Cyan
Write-Host ""
Write-Host "Share the file contents for review." -ForegroundColor Yellow