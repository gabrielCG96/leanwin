BeforeDiscovery {
    $profileCases = @(Get-ChildItem -LiteralPath (Join-Path $PSScriptRoot '..\Config\Profiles') -Filter '*.json' -File |
        Sort-Object Name | ForEach-Object { @{ ProfileName = $_.BaseName; ProfilePath = $_.FullName } })
}

BeforeAll {
    $script:RepoRoot = Join-Path $PSScriptRoot '..'
    $script:FeatureIds = @((Get-Content -LiteralPath (Join-Path $script:RepoRoot 'Config\Features.json') -Raw | ConvertFrom-Json).Features.FeatureId)
    $script:AppIds = @((Get-Content -LiteralPath (Join-Path $script:RepoRoot 'Config\Apps.json') -Raw -Encoding UTF8 | ConvertFrom-Json).Apps | ForEach-Object { $_.AppId })
}

Describe 'Shipped profile: <ProfileName>' -ForEach $profileCases {
    BeforeAll {
        $script:Profile = Get-Content -LiteralPath $ProfilePath -Raw -Encoding UTF8 | ConvertFrom-Json
    }

    It 'uses the config format version understood by -Config' {
        $script:Profile.Version | Should -Be '1.0'
    }

    It 'only enables tweaks that exist in Features.json' {
        $unknown = @($script:Profile.Tweaks | Where-Object { $script:FeatureIds -notcontains $_.Name } | ForEach-Object { $_.Name })
        $unknown | Should -HaveCount 0 -Because ($unknown -join ', ')
    }

    It 'lists each tweak once and only with a true value' {
        $names = @($script:Profile.Tweaks | ForEach-Object { $_.Name })
        @($names | Select-Object -Unique) | Should -HaveCount $names.Count
        @($script:Profile.Tweaks | Where-Object { $_.Value -ne $true }) | Should -HaveCount 0
    }

    It 'only removes apps that exist in Apps.json' {
        $flatIds = @($script:AppIds | ForEach-Object { $_ })
        $unknown = @($script:Profile.Apps | Where-Object { $flatIds -notcontains $_ })
        $unknown | Should -HaveCount 0 -Because ($unknown -join ', ')
    }
}
