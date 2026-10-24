<#
    .SYNOPSIS
    Counts the programs that start with Windows (Run keys and Startup folders).
#>
function Get-StartupItemCount {
    $count = 0
    $runKeys = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run',
               'HKLM:\Software\Microsoft\Windows\CurrentVersion\Run',
               'HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Run'
    foreach ($key in $runKeys) {
        try {
            $item = Get-Item -LiteralPath $key -ErrorAction Stop
            $count += @($item.GetValueNames() | Where-Object { $_ }).Count
        }
        catch { }
    }

    $startupFolders = (Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs\Startup'),
                      (Join-Path $env:ProgramData 'Microsoft\Windows\Start Menu\Programs\Startup')
    foreach ($folder in $startupFolders) {
        if (Test-Path -LiteralPath $folder) {
            $count += @(Get-ChildItem -LiteralPath $folder -File -ErrorAction SilentlyContinue | Where-Object { $_.Name -ne 'desktop.ini' }).Count
        }
    }

    return $count
}

<#
    .SYNOPSIS
    Captures the numbers used by the before/after report.

    .OUTPUTS
    PSCustomObject with the time of the snapshot, memory in use, process count, startup items, free disk space and last boot duration.
#>
function Get-SystemSnapshot {
    $os = Get-CimInstance -ClassName Win32_OperatingSystem
    $totalMB = [math]::Round($os.TotalVisibleMemorySize / 1024)
    $usedMB = $totalMB - [math]::Round($os.FreePhysicalMemory / 1024)

    $freeDiskGB = $null
    try {
        $drive = Get-CimInstance -ClassName Win32_LogicalDisk -Filter "DeviceID='$env:SystemDrive'" -ErrorAction Stop
        $freeDiskGB = [math]::Round($drive.FreeSpace / 1GB, 1)
    }
    catch { }

    # Windows records how long the last boot took (event 100). It only changes after a restart.
    $bootSeconds = $null
    try {
        $bootEvent = Get-WinEvent -FilterHashtable @{ LogName = 'Microsoft-Windows-Diagnostics-Performance/Operational'; Id = 100 } -MaxEvents 1 -ErrorAction Stop
        $bootData = ([xml]$bootEvent.ToXml()).Event.EventData.Data | Where-Object { $_.Name -eq 'BootTime' }
        $bootSeconds = [math]::Round([double]$bootData.'#text' / 1000, 1)
    }
    catch { }

    [PSCustomObject]@{
        CapturedAt       = (Get-Date).ToString('o')
        LastBootTime     = $os.LastBootUpTime.ToString('o')
        MemoryUsedMB     = $usedMB
        MemoryTotalMB    = $totalMB
        ProcessCount     = @(Get-Process).Count
        StartupItems     = Get-StartupItemCount
        FreeDiskGB       = $freeDiskGB
        BootDurationSecs = $bootSeconds
    }
}

<#
    .SYNOPSIS
    Prints a table comparing two snapshots. A lower value is better for every row except free disk space.
#>
function Write-SystemReport {
    param (
        [Parameter(Mandatory)]
        $Before,
        [Parameter(Mandatory)]
        $After,
        [string]$BeforeLabel = 'Before',
        [string]$AfterLabel = 'After'
    )

    $rows = @(
        @{ Name = 'Memory in use (MB)'; Key = 'MemoryUsedMB'; HigherIsBetter = $false },
        @{ Name = 'Running processes'; Key = 'ProcessCount'; HigherIsBetter = $false },
        @{ Name = 'Startup programs'; Key = 'StartupItems'; HigherIsBetter = $false },
        @{ Name = 'Free disk space (GB)'; Key = 'FreeDiskGB'; HigherIsBetter = $true },
        @{ Name = 'Last boot time (s)'; Key = 'BootDurationSecs'; HigherIsBetter = $false }
    )

    Write-Host ""
    Write-Host ("{0,-24}{1,12}{2,12}{3,12}" -f 'System report', $BeforeLabel, $AfterLabel, 'Change') -ForegroundColor Cyan
    foreach ($row in $rows) {
        $b = $Before.($row.Key)
        $a = $After.($row.Key)
        if ($null -eq $b -or $null -eq $a) {
            Write-Host ("{0,-24}{1,12}{2,12}{3,12}" -f $row.Name, "$b", "$a", 'n/a')
            continue
        }

        $delta = [math]::Round(($a - $b), 1)
        $color = 'Gray'
        if ($delta -ne 0) {
            $improved = if ($row.HigherIsBetter) { $delta -gt 0 } else { $delta -lt 0 }
            $color = if ($improved) { 'Green' } else { 'Yellow' }
        }
        $sign = if ($delta -gt 0) { '+' } else { '' }
        Write-Host ("{0,-24}{1,12}{2,12}{3,12}" -f $row.Name, $b, $a, "$sign$delta") -ForegroundColor $color
    }
    Write-Host ""
}

<#
    .SYNOPSIS
    Saves a snapshot as JSON in the Reports folder and returns its path.
#>
function Save-SystemSnapshot {
    param (
        [Parameter(Mandatory)]
        $Snapshot
    )

    $reportsPath = Join-Path $script:UserDataPath 'Reports'
    if (-not (Test-Path -LiteralPath $reportsPath)) {
        New-Item -ItemType Directory -Path $reportsPath -Force | Out-Null
    }

    $filePath = Join-Path $reportsPath ("Snapshot-{0}.json" -f (Get-Date -Format 'yyyyMMdd-HHmmss'))
    $Snapshot | ConvertTo-Json | Set-Content -LiteralPath $filePath -Encoding UTF8
    return $filePath
}

<#
    .SYNOPSIS
    Returns the most recently saved snapshot, or $null when none exists.
#>
function Get-LastSavedSnapshot {
    $reportsPath = Join-Path $script:UserDataPath 'Reports'
    if (-not (Test-Path -LiteralPath $reportsPath)) { return $null }

    $latest = Get-ChildItem -LiteralPath $reportsPath -Filter 'Snapshot-*.json' -File | Sort-Object Name | Select-Object -Last 1
    if (-not $latest) { return $null }

    try { return (Get-Content -LiteralPath $latest.FullName -Raw -Encoding UTF8 | ConvertFrom-Json) }
    catch { return $null }
}
