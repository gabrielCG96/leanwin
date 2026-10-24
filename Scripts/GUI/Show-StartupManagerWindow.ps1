<#
    .SYNOPSIS
        Shows the startup programs of Windows with a switch for each of them.

    .DESCRIPTION
        Every change is applied right away through the same StartupApproved mechanism as Task Manager, so a
        program that is switched off is not deleted and can be switched on again at any time.
#>
function Show-StartupManagerWindow {
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
        $xaml = ConvertTo-LocalizedXaml -Xaml (Get-Content -Path $script:StartupManagerSchema -Raw)
        $reader = [System.Xml.XmlReader]::Create([System.IO.StringReader]::new($xaml))
        try { $window = [System.Windows.Markup.XamlReader]::Load($reader) }
        finally { $reader.Close() }

        if ($ownerWindow) {
            try { $window.Owner = $ownerWindow } catch { }
        }
        Set-WindowThemeResources -window $window -usesDarkMode $usesDarkMode

        $entriesPanel = $window.FindName('EntriesPanel')
        $statusText = $window.FindName('StatusText')
        $closeBtn = $window.FindName('CloseBtn')
        $titleBar = $window.FindName('TitleBar')

        $entries = @(Get-StartupEntries | Sort-Object Name)
        if ($entries.Count -eq 0) {
            $emptyText = New-Object System.Windows.Controls.TextBlock
            $emptyText.Text = Get-Translation -Key 'StartupManagerEmpty'
            $emptyText.SetResourceReference([System.Windows.Controls.TextBlock]::ForegroundProperty, 'AppFgColor')
            $entriesPanel.Children.Add($emptyText) | Out-Null
        }

        foreach ($entry in $entries) {
            $scopeText = Get-Translation -Key $(if ($entry.Scope -eq 'User') { 'StartupManagerScopeUser' } else { 'StartupManagerScopeMachine' })

            $row = New-Object System.Windows.Controls.StackPanel
            $row.Margin = '0,0,0,10'

            $checkBox = New-Object System.Windows.Controls.CheckBox
            $checkBox.Content = "$($entry.Name)  ($scopeText)"
            $checkBox.IsChecked = [bool]$entry.Enabled
            $checkBox.Tag = $entry
            $checkBox.ToolTip = $entry.Command
            $checkBox.SetResourceReference([System.Windows.Controls.CheckBox]::ForegroundProperty, 'AppFgColor')
            $checkBox.Add_Click({
                $clicked = $this.Tag
                $wanted = [bool]$this.IsChecked
                if (Set-StartupEntryState -Entry $clicked -Enabled $wanted) {
                    $clicked.Enabled = $wanted
                    $statusText.Visibility = 'Collapsed'
                }
                else {
                    $this.IsChecked = -not $wanted
                    $statusText.Text = Get-Translation -Key 'StartupManagerChangeFailed' -FormatArgs @($clicked.Name)
                    $statusText.Visibility = 'Visible'
                }
            })

            $commandText = New-Object System.Windows.Controls.TextBlock
            $commandText.Text = $entry.Command
            $commandText.FontSize = 11
            $commandText.Opacity = 0.65
            $commandText.Margin = '22,2,0,0'
            $commandText.TextTrimming = 'CharacterEllipsis'
            $commandText.ToolTip = $entry.Command
            $commandText.SetResourceReference([System.Windows.Controls.TextBlock]::ForegroundProperty, 'AppFgColor')

            $row.Children.Add($checkBox) | Out-Null
            $row.Children.Add($commandText) | Out-Null
            $entriesPanel.Children.Add($row) | Out-Null
        }

        $closeBtn.Add_Click({ $window.Close() })
        $titleBar.Add_MouseLeftButtonDown({ $window.DragMove() })
        $window.Add_KeyDown({
            param($sender, $e)
            if ($e.Key -eq 'Escape') { $window.Close() }
        })

        $window.ShowDialog() | Out-Null
    }
    finally {
        if ($overlay -and -not $overlayWasAlreadyVisible) {
            try { $ownerWindow.Dispatcher.Invoke([action]{ $overlay.Visibility = 'Collapsed' }) } catch { }
        }
    }
}
