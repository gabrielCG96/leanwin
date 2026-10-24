BeforeAll {
    . (Join-Path $PSScriptRoot '..\Scripts\Features\Startup-Manager.ps1')
    . (Join-Path $PSScriptRoot '..\Scripts\FileIO\Update-AppList.ps1')
    $script:BundledAppList = Get-Content -LiteralPath (Join-Path $PSScriptRoot '..\Config\Apps.json') -Raw -Encoding UTF8
}

Describe 'StartupApproved helpers' {
    It 'reads the lowest bit of the first byte as the disabled flag' {
        Test-StartupApprovedDisabled -Bytes ([byte[]](3, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)) | Should -BeTrue
        Test-StartupApprovedDisabled -Bytes ([byte[]](7, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)) | Should -BeTrue
        Test-StartupApprovedDisabled -Bytes ([byte[]](2, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)) | Should -BeFalse
        Test-StartupApprovedDisabled -Bytes ([byte[]](6, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)) | Should -BeFalse
    }

    It 'treats a missing value as enabled' {
        Test-StartupApprovedDisabled -Bytes $null | Should -BeFalse
    }

    It 'builds 12 byte values that round-trip through the reader' {
        $enabled = ConvertTo-StartupApprovedBytes -Enabled $true
        $disabled = ConvertTo-StartupApprovedBytes -Enabled $false

        $enabled.Length | Should -Be 12
        $disabled.Length | Should -Be 12
        Test-StartupApprovedDisabled -Bytes $enabled | Should -BeFalse
        Test-StartupApprovedDisabled -Bytes $disabled | Should -BeTrue
    }
}

Describe 'Find-StartupEntry' {
    BeforeAll {
        $script:Entries = @(
            [PSCustomObject]@{ Name = 'Steam'; Scope = 'User'; Source = 'Registry' }
            [PSCustomObject]@{ Name = 'Updater'; Scope = 'User'; Source = 'Registry' }
            [PSCustomObject]@{ Name = 'updater'; Scope = 'Machine'; Source = 'Registry' }
        )
    }

    It 'matches names without regard to case' {
        (Find-StartupEntry -Name 'STEAM' -Entries $script:Entries).Name | Should -Be 'Steam'
    }

    It 'fails when the name is unknown' {
        { Find-StartupEntry -Name 'Nope' -Entries $script:Entries } | Should -Throw '*No startup item*'
    }

    It 'fails instead of guessing when the name is ambiguous' {
        { Find-StartupEntry -Name 'Updater' -Entries $script:Entries } | Should -Throw '*More than one*'
    }
}

Describe 'Set-StartupEntryState' {
    It 'writes nothing with -WhatIf' {
        $script:Params = @{ WhatIf = $true }
        $entry = [PSCustomObject]@{ Name = 'X'; ApprovedKey = 'HKCU:\Software\LeanWinTestShouldNotExist'; ApprovedName = 'X' }

        Set-StartupEntryState -Entry $entry -Enabled $false | Should -BeTrue

        Test-Path 'HKCU:\Software\LeanWinTestShouldNotExist' | Should -BeFalse
    }
}

Describe 'Test-AppListContent' {
    It 'accepts the app list shipped with the script' {
        Test-AppListContent -Json $script:BundledAppList | Should -BeNullOrEmpty
    }

    It 'rejects <Name>' -ForEach @(
        @{ Name = 'text that is not JSON'; Json = '{ nope' }
        @{ Name = 'an unsupported version'; Replace = @('"Version": "1.1"', '"Version": "9.9"') }
        @{ Name = 'a package identifier with shell characters'; Replace = @('"AppId": "Microsoft.3DBuilder"', '"AppId": "x; calc"') }
        @{ Name = 'an unknown removal method'; Replace = @('"RemovalMethod": "Appx"', '"RemovalMethod": "Cmd"') }
        @{ Name = 'an unknown recommendation'; Replace = @('"Recommendation": "safe"', '"Recommendation": "whatever"') }
    ) {
        $json = if ($Json) { $Json } else { $script:BundledAppList.Replace($Replace[0], $Replace[1]) }

        Test-AppListContent -Json $json | Should -Not -BeNullOrEmpty
    }

    It 'rejects a preset that points at an app that is not in the list' {
        $catalog = $script:BundledAppList | ConvertFrom-Json
        $catalog.Presets[0].AppIds = @($catalog.Presets[0].AppIds) + 'Not.InTheList'

        Test-AppListContent -Json ($catalog | ConvertTo-Json -Depth 10) | Should -BeLike '*unknown app*'
    }

    It 'rejects an unsafe app that is selected by default' {
        $catalog = $script:BundledAppList | ConvertFrom-Json
        $unsafe = $catalog.Apps | Where-Object { $_.Recommendation -eq 'unsafe' } | Select-Object -First 1
        $unsafe.SelectedByDefault = $true

        Test-AppListContent -Json ($catalog | ConvertTo-Json -Depth 10) | Should -BeLike '*unsafe*'
    }
}
