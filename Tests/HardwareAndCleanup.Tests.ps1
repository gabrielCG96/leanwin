BeforeAll {
    . (Join-Path $PSScriptRoot '..\Scripts\Features\Get-HardwareInfo.ps1')
    . (Join-Path $PSScriptRoot '..\Scripts\Features\Get-SystemSnapshot.ps1')
    . (Join-Path $PSScriptRoot '..\Scripts\Features\Clear-DiskJunk.ps1')
}

Describe 'Get-RecommendedProfile' {
    It 'recommends the Laptop profile for portable devices' {
        (Get-RecommendedProfile -IsLaptop $true -HasDiscreteGpu $true -SystemDiskType 'SSD').ProfileName | Should -Be 'Laptop'
    }

    It 'recommends the Gamer profile for a desktop with a dedicated GPU' {
        (Get-RecommendedProfile -IsLaptop $false -HasDiscreteGpu $true -SystemDiskType 'HDD').ProfileName | Should -Be 'Gamer'
    }

    It 'recommends the Minimal profile for a desktop without a dedicated GPU' {
        (Get-RecommendedProfile -IsLaptop $false -HasDiscreteGpu $false -SystemDiskType 'SSD').ProfileName | Should -Be 'Minimal'
    }

    It 'only suggests disabling SysMain when Windows is installed on an SSD' {
        (Get-RecommendedProfile -IsLaptop $false -HasDiscreteGpu $true -SystemDiskType 'SSD').ExtraFeatureIds | Should -Contain 'DisableSysMain'
        (Get-RecommendedProfile -IsLaptop $false -HasDiscreteGpu $true -SystemDiskType 'HDD').ExtraFeatureIds | Should -Not -Contain 'DisableSysMain'
        (Get-RecommendedProfile -IsLaptop $false -HasDiscreteGpu $true -SystemDiskType 'Unknown').ExtraFeatureIds | Should -Not -Contain 'DisableSysMain'
    }

    It 'only recommends profiles that ship in Config/Profiles' {
        $shipped = (Get-ChildItem -LiteralPath (Join-Path $PSScriptRoot '..\Config\Profiles') -Filter '*.json').BaseName
        foreach ($laptop in $true, $false) {
            foreach ($gpu in $true, $false) {
                $shipped | Should -Contain (Get-RecommendedProfile -IsLaptop $laptop -HasDiscreteGpu $gpu).ProfileName
            }
        }
    }
}

Describe 'Remove-FolderContents' {
    BeforeEach {
        $script:Sandbox = Join-Path $TestDrive 'junk'
        New-Item -ItemType Directory -Path (Join-Path $script:Sandbox 'sub') -Force | Out-Null
        $script:OldFile = Join-Path $script:Sandbox 'sub\old.bin'
        $script:NewFile = Join-Path $script:Sandbox 'new.bin'
        [IO.File]::WriteAllBytes($script:OldFile, (New-Object byte[] 2048))
        [IO.File]::WriteAllBytes($script:NewFile, (New-Object byte[] 1024))
        (Get-Item $script:OldFile).LastWriteTime = (Get-Date).AddDays(-3)
    }

    It 'deletes only files older than the cutoff and removes folders left empty' {
        $script:Params = @{}

        Remove-FolderContents -Path $script:Sandbox -OlderThanDays 1 | Should -Be 2048

        Test-Path $script:OldFile | Should -BeFalse
        Test-Path (Join-Path $script:Sandbox 'sub') | Should -BeFalse
        Test-Path $script:NewFile | Should -BeTrue
    }

    It 'reports the size but deletes nothing with -WhatIf' {
        $script:Params = @{ WhatIf = $true }

        Remove-FolderContents -Path $script:Sandbox -OlderThanDays 1 | Should -Be 2048

        Test-Path $script:OldFile | Should -BeTrue
    }

    It 'returns zero for a folder that does not exist' {
        $script:Params = @{}

        Remove-FolderContents -Path (Join-Path $TestDrive 'missing') | Should -Be 0
    }
}

Describe 'Write-SystemReport' {
    It 'handles snapshots with missing values' {
        $before = [PSCustomObject]@{ MemoryUsedMB = 100; ProcessCount = 10; StartupItems = 3; FreeDiskGB = $null; BootDurationSecs = $null }
        $after = [PSCustomObject]@{ MemoryUsedMB = 90; ProcessCount = 9; StartupItems = 3; FreeDiskGB = $null; BootDurationSecs = $null }

        { Write-SystemReport -Before $before -After $after 6>$null } | Should -Not -Throw
    }
}
