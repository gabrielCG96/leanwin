<#
    .SYNOPSIS
        Shows a short questionnaire in plain language and returns what to select in the Tweaks tab.

    .DESCRIPTION
        For people who do not know the Windows services and settings listed in the custom mode. The answers pick one
        of the shipped profiles plus a few extras, and a summary lists every tweak that will be selected, so nothing
        happens without being visible first. The window only returns the choice, the caller does the selecting.

    .OUTPUTS
        PSCustomObject with ProfileName, ExtraFeatureIds and SelectDefaultApps, or $null when canceled.
#>
function Show-GuidedSetupWindow {
    param(
        [System.Windows.Window]$Owner = $null
    )

    Add-Type -AssemblyName PresentationFramework,PresentationCore,WindowsBase | Out-Null

    $usesDarkMode = Get-AppUsesDarkMode
    $ownerWindow = if ($Owner) { $Owner } else { $script:GuiWindow }

    $overlay = $null
    $overlayWasAlreadyVisible = $false
    if ($ownerWindow) {
        try {
            $overlay = $ownerWindow.FindName('ModalOverlay')
            if ($overlay) {
                $overlayWasAlreadyVisible = ($overlay.Visibility -eq 'Visible')
                if (-not $overlayWasAlreadyVisible) {
                    $ownerWindow.Dispatcher.Invoke([action]{ $overlay.Visibility = 'Visible' })
                }
            }
        }
        catch { }
    }

    try {
        $xaml = ConvertTo-LocalizedXaml -Xaml (Get-Content -Path $script:GuidedSetupSchema -Raw)
        $reader = [System.Xml.XmlReader]::Create([System.IO.StringReader]::new($xaml))
        try { $window = [System.Windows.Markup.XamlReader]::Load($reader) }
        finally { $reader.Close() }

        if ($ownerWindow) {
            try { $window.Owner = $ownerWindow } catch { }
        }
        Set-WindowThemeResources -window $window -usesDarkMode $usesDarkMode

        $useCombo = $window.FindName('UseCombo')
        $hardwareLine = $window.FindName('HardwareLine')
        $extraSpace = $window.FindName('ExtraSpace')
        $extraStartup = $window.FindName('ExtraStartup')
        $extraApps = $window.FindName('ExtraApps')
        $summaryDescription = $window.FindName('SummaryDescription')
        $summaryList = $window.FindName('SummaryList')

        # What this PC is, so "choose for me" has something to work from
        $hardwareInfo = Get-HardwareInfo
        $recommendation = Get-RecommendedProfile -IsLaptop $hardwareInfo.IsLaptop -HasDiscreteGpu $hardwareInfo.HasDiscreteGpu -SystemDiskType $hardwareInfo.SystemDiskType
        $deviceType = Get-Translation -Key $(if ($hardwareInfo.IsLaptop) { 'HardwareDeviceLaptop' } else { 'HardwareDeviceDesktop' })
        $hardwareLine.Text = Get-Translation -Key 'GuidedHardwareLine' -FormatArgs @($deviceType, $hardwareInfo.SystemDiskType)

        $profilesByName = @{}
        foreach ($shippedProfile in Get-ShippedProfiles) { $profilesByName[$shippedProfile.Name] = $shippedProfile }

        $choiceByIndex = @('Auto', 'Gamer', 'Laptop', 'Privacy', 'Minimal')
        $window.Tag = $null

        # Works out what the current answers mean: the profile, the extra tweaks and whether to pick the default apps
        $getChoice = {
            $selected = $choiceByIndex[[math]::Max(0, $useCombo.SelectedIndex)]
            $extraIds = @()
            $profileName = $selected
            if ($selected -eq 'Auto') {
                $profileName = $recommendation.ProfileName
                $extraIds += @($recommendation.ExtraFeatureIds)
            }
            if ($extraSpace.IsChecked) { $extraIds += 'CleanTempFiles', 'CleanWindowsUpdateCache' }
            if ($extraStartup.IsChecked) { $extraIds += 'DisableStartupDelay' }
            [PSCustomObject]@{
                ProfileName      = $profileName
                ExtraFeatureIds  = @($extraIds | Select-Object -Unique)
                SelectDefaultApps = [bool]$extraApps.IsChecked
            }
        }

        $updateSummary = {
            $choice = & $getChoice
            $profileLabel = Get-Translation -Key "ProfileName_$($choice.ProfileName)"
            if ($profileLabel -eq "ProfileName_$($choice.ProfileName)") { $profileLabel = $choice.ProfileName }

            $summaryList.Children.Clear()
            $featureIds = @()
            if ($profilesByName.ContainsKey($choice.ProfileName)) {
                $featureIds += @($profilesByName[$choice.ProfileName].Tweaks | ForEach-Object { $_.Name })
            }
            $featureIds += $choice.ExtraFeatureIds
            $featureIds = @($featureIds | Select-Object -Unique)

            $summaryDescription.Text = Get-Translation -Key 'GuidedSummaryDescription' -FormatArgs @($profileLabel, $featureIds.Count)

            foreach ($featureId in $featureIds) {
                $label = Get-Translation -Key $featureId -Field 'Label' -Section 'Features'
                $line = [System.Windows.Controls.TextBlock]::new()
                $line.Text = "$([char]0x2022) $label"
                $line.FontSize = 12
                $line.TextWrapping = 'Wrap'
                $line.Opacity = 0.9
                $line.Margin = [System.Windows.Thickness]::new(0, 2, 0, 0)
                $tip = Get-Translation -Key $featureId -Field 'ToolTip' -Section 'Features'
                if ($tip -and $tip -ne $featureId) { $line.ToolTip = $tip }
                $line.SetResourceReference([System.Windows.Controls.TextBlock]::ForegroundProperty, 'AppFgColor')
                $summaryList.Children.Add($line) | Out-Null
            }

            if ($choice.SelectDefaultApps) {
                $appsLine = [System.Windows.Controls.TextBlock]::new()
                $appsLine.Text = "$([char]0x2022) $(Get-Translation -Key 'GuidedSummaryApps')"
                $appsLine.FontSize = 12
                $appsLine.TextWrapping = 'Wrap'
                $appsLine.Margin = [System.Windows.Thickness]::new(0, 6, 0, 0)
                $appsLine.SetResourceReference([System.Windows.Controls.TextBlock]::ForegroundProperty, 'AppFgColor')
                $summaryList.Children.Add($appsLine) | Out-Null
            }
        }

        $useCombo.Add_SelectionChanged($updateSummary)
        foreach ($checkBox in @($extraSpace, $extraStartup, $extraApps)) {
            $checkBox.Add_Checked($updateSummary)
            $checkBox.Add_Unchecked($updateSummary)
        }
        & $updateSummary

        $window.FindName('CancelBtn').Add_Click({ $window.Tag = $null; $window.Close() })
        $window.FindName('SelectBtn').Add_Click({ $window.Tag = (& $getChoice); $window.Close() })
        $window.FindName('TitleBar').Add_MouseLeftButtonDown({ $window.DragMove() })
        $window.Add_KeyDown({
            param($sender, $e)
            if ($e.Key -eq 'Escape') { $window.Tag = $null; $window.Close() }
        })

        $window.ShowDialog() | Out-Null
        return $window.Tag
    }
    finally {
        if ($overlay -and -not $overlayWasAlreadyVisible) {
            try { $ownerWindow.Dispatcher.Invoke([action]{ $overlay.Visibility = 'Collapsed' }) } catch { }
        }
    }
}
