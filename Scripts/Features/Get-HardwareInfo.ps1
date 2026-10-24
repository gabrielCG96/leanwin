<#
    .SYNOPSIS
    Detects the hardware traits that decide which profile fits this PC.

    .OUTPUTS
    PSCustomObject with SystemDiskType (SSD, HDD or Unknown), BusType, IsLaptop, Gpus, HasDiscreteGpu, TotalRamGB and ComputerModel.
#>
function Get-HardwareInfo {
    $diskType = 'Unknown'
    $busType = $null
    try {
        $driveLetter = $env:SystemDrive.TrimEnd(':')
        $diskNumber = (Get-Partition -DriveLetter $driveLetter -ErrorAction Stop).DiskNumber
        $physicalDisk = Get-PhysicalDisk -ErrorAction Stop | Where-Object { [string]$_.DeviceId -eq [string]$diskNumber } | Select-Object -First 1
        if ($physicalDisk) {
            $busType = [string]$physicalDisk.BusType
            if ($physicalDisk.MediaType -in 'SSD', 'HDD') { $diskType = [string]$physicalDisk.MediaType }
            elseif ($busType -eq 'NVMe') { $diskType = 'SSD' }
        }
    }
    catch { Write-Verbose "Unable to detect the system disk type: $($_.Exception.Message)" }

    # Chassis types that Windows reports for portable devices (laptop, notebook, tablet, convertible, detachable and similar)
    $portableChassisTypes = 8, 9, 10, 11, 12, 14, 18, 21, 30, 31, 32
    $isLaptop = $false
    try {
        $hasBattery = $null -ne (Get-CimInstance -ClassName Win32_Battery -ErrorAction Stop | Select-Object -First 1)
        $chassisTypes = @((Get-CimInstance -ClassName Win32_SystemEnclosure -ErrorAction Stop).ChassisTypes)
        $isLaptop = $hasBattery -or [bool]($chassisTypes | Where-Object { $portableChassisTypes -contains [int]$_ })
    }
    catch { Write-Verbose "Unable to detect the device type: $($_.Exception.Message)" }

    $gpuNames = @()
    try { $gpuNames = @(Get-CimInstance -ClassName Win32_VideoController -ErrorAction Stop | ForEach-Object { [string]$_.Name } | Where-Object { $_ }) }
    catch { Write-Verbose "Unable to detect the GPU: $($_.Exception.Message)" }
    $hasDiscreteGpu = [bool]($gpuNames | Where-Object { $_ -match 'NVIDIA|GeForce|Radeon RX|Radeon Pro|Arc\b' })

    $ramGB = $null
    $model = $null
    try {
        $system = Get-CimInstance -ClassName Win32_ComputerSystem -ErrorAction Stop
        $ramGB = [math]::Round($system.TotalPhysicalMemory / 1GB)
        $model = "$($system.Manufacturer) $($system.Model)".Trim()
    }
    catch { Write-Verbose "Unable to read the computer model: $($_.Exception.Message)" }

    [PSCustomObject]@{
        SystemDiskType = $diskType
        BusType        = $busType
        IsLaptop       = $isLaptop
        Gpus           = $gpuNames
        HasDiscreteGpu = $hasDiscreteGpu
        TotalRamGB     = $ramGB
        ComputerModel  = $model
    }
}

<#
    .SYNOPSIS
    Picks the profile from Config/Profiles that suits the detected hardware.

    .OUTPUTS
    PSCustomObject with ProfileName, ExtraFeatureIds and Reasons.
#>
function Get-RecommendedProfile {
    param (
        [bool]$IsLaptop,
        [bool]$HasDiscreteGpu,
        [string]$SystemDiskType = 'Unknown'
    )

    $reasons = @()
    $extraFeatureIds = @()

    if ($IsLaptop) {
        $profileName = 'Laptop'
        $reasons += 'This is a portable device, so battery life matters more than raw performance.'
    }
    elseif ($HasDiscreteGpu) {
        $profileName = 'Gamer'
        $reasons += 'This is a desktop with a dedicated GPU, so the performance profile fits.'
    }
    else {
        $profileName = 'Minimal'
        $reasons += 'This is a desktop without a dedicated GPU, so the low-risk profile is the safest start.'
    }

    if ($SystemDiskType -eq 'SSD') {
        $extraFeatureIds += 'DisableSysMain'
        $reasons += 'Windows is installed on an SSD, so the SysMain (Superfetch) service brings little benefit and can be disabled.'
    }
    elseif ($SystemDiskType -eq 'HDD') {
        $reasons += 'Windows is installed on a hard disk, so the SysMain (Superfetch) service is kept because it helps there.'
    }

    [PSCustomObject]@{
        ProfileName     = $profileName
        ExtraFeatureIds = $extraFeatureIds
        Reasons         = $reasons
    }
}

<#
    .SYNOPSIS
    Prints the detected hardware and the recommended profile.
#>
function Write-HardwareRecommendation {
    param (
        [Parameter(Mandatory)]
        $Info,
        [Parameter(Mandatory)]
        $Recommendation
    )

    Write-Host "Detected hardware" -ForegroundColor Cyan
    Write-Host "  Model:        $($Info.ComputerModel)"
    Write-Host "  Device type:  $(if ($Info.IsLaptop) { 'Laptop / portable' } else { 'Desktop' })"
    Write-Host "  System disk:  $($Info.SystemDiskType)$(if ($Info.BusType) { " ($($Info.BusType))" })"
    Write-Host "  GPU:          $(if ($Info.Gpus.Count -gt 0) { $Info.Gpus -join ', ' } else { 'Unknown' })"
    Write-Host "  RAM:          $(if ($Info.TotalRamGB) { "$($Info.TotalRamGB) GB" } else { 'Unknown' })"
    Write-Host ""
    Write-Host "Recommended profile: $($Recommendation.ProfileName)" -ForegroundColor Green
    foreach ($reason in $Recommendation.Reasons) { Write-Host "  - $reason" }
    Write-Host ""
    Write-Host "Apply it with: .\Win11Debloat.ps1 -ProfileName Auto"
}
