<#
    .SYNOPSIS
    Applies light or dark theme colors to a WPF window's resource dictionary.

    .DESCRIPTION
    Iterates over a predefined set of theme color categories and
    populates the window's Resources with SolidColorBrush entries keyed by
    category and resource name (e.g. "AppAccentColor"). Additionally loads and
    merges shared XAML styles from the script's SharedStylesSchema path if
    available. Also resolves the icon font: Segoe Fluent Icons on Windows 11
    and Segoe MDL2 Assets on Windows 10.

    .PARAMETER window
    The WPF Window whose resource dictionary will be populated.

    .PARAMETER usesDarkMode
    When $true, dark theme colors are applied; when $false, light theme colors.

    .EXAMPLE
    Set-WindowThemeResources -window $MainWindow -usesDarkMode $true

    .EXAMPLE
    Set-WindowThemeResources -window $Dialog -usesDarkMode $false
#>
# Sets resource colors for a WPF window based on dark mode preference
function Set-WindowThemeResources {
    param (
        $window,
        [bool]$usesDarkMode
    )

    # LEANWIN brand palette: Void, Panel and Ice for the dark theme, a darkened Volt Lime for the light theme
    $ThemeColor = @{
        App = @{
            AccentColor = @{ Light = '#5e7f00'; Dark = '#c8ff2e' }
            BorderColor = @{ Light = '#dde1e8'; Dark = '#262a35' }
            BgColor     = @{ Light = '#f2f4f7'; Dark = '#0a0b0f' }
            FgColor     = @{ Light = '#0a0b0f'; Dark = '#f2f4f7' }
            IdColor     = @{ Light = '#5b6270'; Dark = '#9aa3b2' }
        }

        Card = @{
            BgColor = @{ Light = '#ffffff'; Dark = '#14161d' }
        }

        Button = @{
            BorderColor       = @{ Light = '#cbd1db'; Dark = '#262a35' }
            BgColor           = @{ Light = '#5e7f00'; Dark = '#c8ff2e' }
            DisabledColor     = @{ Light = '#c9ced7'; Dark = '#262a35' }
            HoverColor        = @{ Light = '#6e9400'; Dark = '#d6ff5c' }
            PressedColor      = @{ Light = '#4b6700'; Dark = '#aee01a' }
            TextColor         = @{ Light = '#ffffff'; Dark = '#0a0b0f' }
            TextDisabledColor = @{ Light = '#ffffff'; Dark = '#6b7385' }
        }

        SecondaryButton = @{
            BgColor           = @{ Light = '#ffffff'; Dark = '#1b1e27' }
            DisabledColor     = @{ Light = '#f2f4f7'; Dark = '#14161d' }
            HoverColor        = @{ Light = '#eef0f4'; Dark = '#232733' }
            PressedColor      = @{ Light = '#e3e6ec'; Dark = '#14161d' }
            TextDisabledColor = @{ Light = '#a7aebb'; Dark = '#6b7385' }
        }

        CheckBox = @{
            BgColor     = @{ Light = '#ffffff'; Dark = '#14161d' }
            BorderColor = @{ Light = '#7a8394'; Dark = '#6b7385' }
            HoverColor  = @{ Light = '#eef0f4'; Dark = '#1b1e27' }
        }

        ComboBox = @{
            BgColor           = @{ Light = '#ffffff'; Dark = '#14161d' }
            HoverColor        = @{ Light = '#eef0f4'; Dark = '#1b1e27' }
            ItemBgColor       = @{ Light = '#ffffff'; Dark = '#14161d' }
            ItemHoverColor    = @{ Light = '#eef0f4'; Dark = '#1b1e27' }
            ItemSelectedColor = @{ Light = '#e3e6ec'; Dark = '#232733' }
        }

        TextBox = @{
            BorderColor     = @{ Light = '#b6bdc9'; Dark = '#4a5162' }
            BgColor         = @{ Light = '#ffffff'; Dark = '#14161d' }
            FocusColor      = @{ Light = '#ffffff'; Dark = '#0a0b0f' }
            HoverColor      = @{ Light = '#f5f6f9'; Dark = '#1b1e27' }
            SideBorderColor = @{ Light = '#dde1e8'; Dark = '#262a35' }
        }

        ScrollBar = @{
            ThumbColor      = @{ Light = '#b6bdc9'; Dark = '#2f3441' }
            ThumbHoverColor = @{ Light = '#8a93a5'; Dark = '#444b5c' }
        }

        TitleBar = @{
            ButtonHoverColor   = @{ Light = '#dde1e8'; Dark = '#1b1e27' }
            ButtonPressedColor = @{ Light = '#cbd1db'; Dark = '#232733' }
            CloseHoverColor    = @{ Light = '#ff4b3a'; Dark = '#ff4b3a' }
            ClosePressedColor  = @{ Light = '#ff8a7e'; Dark = '#ff8a7e' }
            UnfocusedFgColor   = @{ Light = '#8a93a5'; Dark = '#6b7385' }
        }

        Search = @{
            HighlightActiveColor = @{ Light = '#c8ff2e'; Dark = '#5e7f00' }
            HighlightColor       = @{ Light = '#eaf9b8'; Dark = '#2a3410' }
        }

        Table = @{
            HeaderColor = @{ Light = '#ffffff'; Dark = '#14161d' }
        }

        Icon = @{
            ErrorColor       = @{ Light = '#ff4b3a'; Dark = '#ff4b3a' }
            InformationColor = @{ Light = '#0078d4'; Dark = '#4da3ff' }
            QuestionColor    = @{ Light = '#0078d4'; Dark = '#4da3ff' }
            SuccessColor     = @{ Light = '#5e7f00'; Dark = '#c8ff2e' }
            WarningColor     = @{ Light = '#ffb900'; Dark = '#ffb900' }
        }
    }

    $Theme = if ($usesDarkMode) { 'Dark' } else { 'Light' }
    $window.Resources['AppUsesDarkMode'] = $usesDarkMode

    foreach ($Group in $ThemeColor.GetEnumerator()) {
        foreach ($Resource in $Group.Value.GetEnumerator()) {
            $ResourceName = $Group.Key + $Resource.Key
            $window.Resources[$ResourceName] = [System.Windows.Media.SolidColorBrush]::new(
                [System.Windows.Media.ColorConverter]::ConvertFromString($Resource.Value[$Theme])
            )
        }
    }

    # Segoe Fluent Icons ships only on Windows 11 (build >= 22000). 
    # On Windows 10, fall back to Segoe MDL2 Assets.
    $winBuild = Get-ItemPropertyValue 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion' CurrentBuild
    $iconFontName = if ($winBuild -ge 22000) { 'Segoe Fluent Icons' } else { 'Segoe MDL2 Assets' }
    $window.Resources['AppIconFontFamily'] = [System.Windows.Media.FontFamily]::new($iconFontName)

    # Load and merge shared styles
    if (-not $window.Resources.Contains('AppSharedStylesLoaded') -and $script:SharedStylesSchema -and (Test-Path $script:SharedStylesSchema)) {
        $sharedXaml = Get-Content -Path $script:SharedStylesSchema -Raw
        $sharedReader = [System.Xml.XmlReader]::Create([System.IO.StringReader]::new($sharedXaml))
        try {
            $sharedDict = [System.Windows.Markup.XamlReader]::Load($sharedReader)
            $window.Resources.MergedDictionaries.Add($sharedDict)
            $window.Resources['AppSharedStylesLoaded'] = $true
        }
        finally {
            $sharedReader.Close()
        }
    }
}
