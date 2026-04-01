BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '..' 'llamarc42.psd1') -Force

    $aiRoot      = Join-Path $TestDrive 'ai'
    $globalDir   = Join-Path $aiRoot 'global'
    $projectsDir = Join-Path $aiRoot 'projects'
    $projectDir  = Join-Path $projectsDir 'myproject'

    New-Item -ItemType Directory -Path $globalDir  -Force | Out-Null
    New-Item -ItemType Directory -Path $projectDir -Force | Out-Null

    # Global always-include file
    Set-Content -Path (Join-Path $globalDir 'global-notes.md') -Value 'Global notes'

    # Project files
    $docsDir = Join-Path $projectDir 'docs'
    New-Item -ItemType Directory -Path $docsDir -Force | Out-Null
    Set-Content -Path (Join-Path $projectDir 'spec.md')        -Value 'Spec content'
    Set-Content -Path (Join-Path $docsDir      'design.md')    -Value 'Design content'
    Set-Content -Path (Join-Path $docsDir      'runbook.md')   -Value 'Runbook content'

    # Build a fake policy object (bypasses YAML dependency)
    $fakePolicy = [pscustomobject]@{
        PSTypeName = 'Llamarc42.RetrievalPolicy'
        Path       = 'fake.yaml'
        Policy     = @{
            version = 1
            global  = @{
                always_include = @('global-notes.md')
            }
            project = @{
                include = @('spec.md')
                folders = @{
                    docs = @{ priority = 'high' }
                }
            }
            retrieval = @{
                strategies = @{
                    general = @{
                        include   = @('docs/*.md')
                        max_files = 0
                    }
                    planning = @{
                        include   = @('docs/*.md')
                        max_files = 0
                    }
                    coding = @{
                        include   = @('docs/*.md')
                        max_files = 0
                    }
                    review = @{
                        include   = @('docs/*.md')
                        max_files = 0
                    }
                }
            }
        }
    }
}

AfterAll {
    Remove-Module llamarc42 -Force -ErrorAction SilentlyContinue
}

Describe 'Resolve-Llamarc42RetrievalContext' {
    Context 'Return object shape' {
        It 'returns an object with PSTypeName Llamarc42.RetrievalContext' {
            $result = Resolve-Llamarc42RetrievalContext -ProjectFolder $projectDir -Policy $fakePolicy
            $result.PSObject.TypeNames[0] | Should -Be 'Llamarc42.RetrievalContext'
        }

        It 'returns an object with an Items collection' {
            $result = Resolve-Llamarc42RetrievalContext -ProjectFolder $projectDir -Policy $fakePolicy
            $result.PSObject.Properties.Name | Should -Contain 'Items'
        }

        It 'returns an object with a Files list' {
            $result = Resolve-Llamarc42RetrievalContext -ProjectFolder $projectDir -Policy $fakePolicy
            $result.PSObject.Properties.Name | Should -Contain 'Files'
        }

        It 'echoes the resolved intent' {
            $result = Resolve-Llamarc42RetrievalContext -Intent planning -ProjectFolder $projectDir -Policy $fakePolicy
            $result.Intent | Should -Be 'planning'
        }
    }

    Context 'Global always_include items' {
        It 'includes the global always-include file' {
            $result = Resolve-Llamarc42RetrievalContext -ProjectFolder $projectDir -Policy $fakePolicy
            $globalItem = $result.Items | Where-Object { $_.Scope -eq 'global' }
            $globalItem | Should -Not -BeNullOrEmpty
        }

        It 'marks the global item Reason as global.always_include' {
            $result   = Resolve-Llamarc42RetrievalContext -ProjectFolder $projectDir -Policy $fakePolicy
            $global   = $result.Items | Where-Object { $_.Scope -eq 'global' } | Select-Object -First 1
            $global.Reason | Should -Be 'global.always_include'
        }
    }

    Context 'Project base include items' {
        It 'includes files matching the project include pattern' {
            $result      = Resolve-Llamarc42RetrievalContext -ProjectFolder $projectDir -Policy $fakePolicy
            $projectBase = $result.Items | Where-Object { $_.Reason -eq 'project.include' }
            $projectBase | Should -Not -BeNullOrEmpty
        }
    }

    Context 'Intent strategy items' {
        It 'includes files matching the strategy include pattern' {
            $result         = Resolve-Llamarc42RetrievalContext -ProjectFolder $projectDir -Policy $fakePolicy
            $strategyItems  = $result.Items | Where-Object { $_.Reason -like 'retrieval.strategies.*' }
            $strategyItems | Should -Not -BeNullOrEmpty
        }
    }

    Context 'Deduplication' {
        It 'does not return the same file path twice' {
            $result  = Resolve-Llamarc42RetrievalContext -ProjectFolder $projectDir -Policy $fakePolicy
            $paths   = $result.Items | ForEach-Object { $_.FullPath }
            $unique  = $paths | Sort-Object -Unique
            $paths.Count | Should -Be $unique.Count
        }
    }

    Context 'Ordering' {
        It 'returns items sorted by OrderRank' {
            $result  = Resolve-Llamarc42RetrievalContext -ProjectFolder $projectDir -Policy $fakePolicy
            $ranks   = $result.Items | ForEach-Object { $_.OrderRank }
            $sorted  = $ranks | Sort-Object
            $ranks | Should -Be $sorted
        }
    }

    Context 'Invalid intent in policy' {
        It 'throws when the policy has no strategy for the given intent' {
            $noStrategyPolicy = [pscustomobject]@{
                PSTypeName = 'Llamarc42.RetrievalPolicy'
                Path       = 'fake.yaml'
                Policy     = @{
                    version   = 1
                    global    = @{ always_include = @() }
                    project   = @{ include = @(); folders = @{} }
                    retrieval = @{ strategies = @{} }
                }
            }
            { Resolve-Llamarc42RetrievalContext -Intent general -ProjectFolder $projectDir -Policy $noStrategyPolicy } |
                Should -Throw
        }
    }
}
