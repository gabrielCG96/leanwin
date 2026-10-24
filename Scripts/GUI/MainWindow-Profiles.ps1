$script:ProfilePresetMaps = @{}
$script:ProfilePresetCheckBoxes = @()

<#
    .SYNOPSIS
        Reads the profiles shipped in Config/Profiles.

    .OUTPUTS
        PSCustomObject with Name, Description and Tweaks for each valid profile file.
#>
function Get-ShippedProfiles {
    $profilesPath = Join-Path $script:ConfigPath 'Profiles'
    if (-not (Test-Path -LiteralPath $profilesPath)) { return @() }

    $profiles = @()
    foreach ($file in Get-ChildItem -LiteralPath $profilesPath -Filter '*.json' -File | Sort-Object Name) {
        try {
            $json = Get-Content -LiteralPath $file.FullName -Raw -Encoding UTF8 | ConvertFrom-Json -ErrorAction Stop
        }
        catch {
            Write-Warning "Skipping profile '$($file.Name)': $($_.Exception.Message)"
            continue
        }
        if (-not $json.Tweaks) { continue }

        $profiles += [PSCustomObject]@{
            Name        = $file.BaseName
            Description = [string]$json.Description
            Tweaks      = @($json.Tweaks)
        }
    }

    return $profiles
}

<#
    .SYNOPSIS
        Adds a tri-state checkbox to the tweak presets menu for every shipped profile.

    .DESCRIPTION
        Profiles behave like the other presets: selecting one checks its tweaks, and the box shows a partial
        state when only some of its tweaks are checked. Profiles only select tweaks, the app list stays as is.
#>
function Initialize-ProfilePresets {
    param(
        [System.Windows.Window]$Window
    )

    $panel = $Window.FindName('ProfilePresetsPanel')
    $header = $Window.FindName('ProfilePresetsHeader')
    if (-not $panel) { return }

    $panel.Children.Clear()
    $script:ProfilePresetMaps = @{}
    $script:ProfilePresetCheckBoxes = @()

    foreach ($shippedProfile in Get-ShippedProfiles) {
        $map = Get-TweakPresetControlMap -Window $Window -SettingsJson ([PSCustomObject]@{ Settings = $shippedProfile.Tweaks })
        if ($map.Count -eq 0) { continue }

        $label = Get-Translation -Key "ProfileName_$($shippedProfile.Name)"
        if ($label -eq "ProfileName_$($shippedProfile.Name)") { $label = $shippedProfile.Name }

        $checkBox = New-Object System.Windows.Controls.CheckBox
        $checkBox.Content = $label
        $checkBox.IsThreeState = $true
        $checkBox.Tag = $shippedProfile.Name
        if ($shippedProfile.Description) { $checkBox.ToolTip = $shippedProfile.Description }
        $checkBox.Style = $Window.FindResource('PresetCheckBoxStyle')
        $checkBox.SetResourceReference([System.Windows.Controls.CheckBox]::ForegroundProperty, 'AppFgColor')
        [System.Windows.Automation.AutomationProperties]::SetName($checkBox, $label)

        Add-TriStateClickBehavior -CheckBox $checkBox
        $checkBox.Add_Click({
            if ($script:UpdatingTweakPresets) { return }
            $check = ConvertTo-NormalizedCheckboxState -CheckBox $this
            Invoke-ApplyTweakPresetMap -PresetMap $script:ProfilePresetMaps[[string]$this.Tag] -Check $check
        })

        $script:ProfilePresetMaps[$shippedProfile.Name] = $map
        $script:ProfilePresetCheckBoxes += $checkBox
        $panel.Children.Add($checkBox) | Out-Null
    }

    $visibility = if ($script:ProfilePresetCheckBoxes.Count -gt 0) { 'Visible' } else { 'Collapsed' }
    $panel.Visibility = $visibility
    if ($header) { $header.Visibility = $visibility }
}

<#
    .SYNOPSIS
        Refreshes the checked, partial or unchecked state of every profile checkbox.
#>
function Update-ProfilePresetStates {
    foreach ($checkBox in $script:ProfilePresetCheckBoxes) {
        Set-TweakPresetCheckBoxState -PresetCheckBox $checkBox -PresetMap $script:ProfilePresetMaps[[string]$checkBox.Tag]
    }
}

<#
    .SYNOPSIS
        Selects the tweaks of one profile, as if its checkbox was ticked.
#>
function Select-ProfilePreset {
    param([string]$Name)

    if ($script:ProfilePresetMaps.ContainsKey($Name)) {
        Invoke-ApplyTweakPresetMap -PresetMap $script:ProfilePresetMaps[$Name] -Check $true
    }
}

<#
    .SYNOPSIS
        Selects one tweak by its FeatureId, as if its checkbox was ticked.

    .OUTPUTS
        System.Boolean. $false when the tweak has no checkbox in this window (for example on an older Windows build).
#>
function Select-FeatureControl {
    param(
        [System.Windows.Window]$Window,
        [string]$FeatureId
    )

    foreach ($controlName in $script:UiControlMappings.Keys) {
        $mapping = $script:UiControlMappings[$controlName]
        if ($mapping.Type -ne 'feature' -or $mapping.FeatureId -ne $FeatureId) { continue }

        $control = $Window.FindName($controlName)
        if ($control -is [System.Windows.Controls.CheckBox] -and $control.Visibility -eq 'Visible') {
            $control.IsChecked = $true
            return $true
        }
    }
    return $false
}
