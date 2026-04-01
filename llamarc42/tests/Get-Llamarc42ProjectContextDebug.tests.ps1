BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '..' 'llamarc42.psd1') -Force

    $aiRoot      = Join-Path $TestDrive 'ai'
    $globalDir   = Join-Path $aiRoot 'global'
    $projectsDir = Join-Path $aiRoot 'projects'
    $projectDir  = Join-Path $projectsDir 'myproject'

    New-Item -ItemType Directory -Path $globalDir  -Force | Out-Null
    New-Item -ItemType Directory -Path $projectDir -Force | Out-Null

    Set-Content -Path (Join-Path $globalDir  'global-notes.md') -Value 'Global notes'
    Set-Content -Path (Join-Path $projectDir 'spec.md')         -Value 'Project spec'

    $fakePolicy = [pscustomobject]@{
        PSTypeName = 'Llamarc42.RetrievalPolicy'
        Path       = 'fake.yaml'
        Policy     = @{
            version   = 1
            global    = @{ always_include = @() }
            project   = @{ include = @(); folders = @{} }
            history   = $null
            retrieval = @{ strategies = @{
                general  = @{ include = @(); max_files = 0 }
                planning = @{ include = @(); max_files = 0 }
                coding   = @{ include = @(); max_files = 0 }
                review   = @{ include = @(); max_files = 0 }
            }}
        }
    }

    $fakeContext = [pscustomobject]@{
        PSTypeName    = 'Llamarc42.RetrievalContext'
        PolicyPath    = 'fake.yaml'
        Intent        = 'general'
        ProjectFolder = $projectDir
        GlobalFolder  = $globalDir
        Items         = @()
        Files         = @()
    }
}

AfterAll {
    Remove-Module llamarc42 -Force -ErrorAction SilentlyContinue
}

Describe 'Get-Llamarc42ProjectContextDebug' {
    BeforeEach {
        Mock Get-Llamarc42RetrievalPolicy      -ModuleName llamarc42 { $fakePolicy }
        Mock Resolve-Llamarc42RetrievalContext -ModuleName llamarc42 { $fakeContext }
    }

    Context 'Return object shape' {
        It 'returns a Llamarc42.ContextDebug object' {
            $result = Get-Llamarc42ProjectContextDebug -ProjectFolder $projectDir
            $result.PSObject.TypeNames[0] | Should -Be 'Llamarc42.ContextDebug'
        }

        It 'includes all expected properties' {
            $result = Get-Llamarc42ProjectContextDebug -ProjectFolder $projectDir
            $props = $result.PSObject.Properties.Name
            $props | Should -Contain 'Intent'
            $props | Should -Contain 'ProjectFolder'
            $props | Should -Contain 'GlobalFolder'
            $props | Should -Contain 'PolicyPath'
            $props | Should -Contain 'HistoryMaxMessages'
            $props | Should -Contain 'HistorySummarizeAfter'
            $props | Should -Contain 'Files'
        }
    }

    Context 'Intent handling' {
        It 'defaults to the general intent' {
            $result = Get-Llamarc42ProjectContextDebug -ProjectFolder $projectDir
            $result.Intent | Should -Be 'general'
        }

        It 'reflects the planning intent when supplied' {
            $result = Get-Llamarc42ProjectContextDebug -ProjectFolder $projectDir -Intent planning
            $result.Intent | Should -Be 'planning'
        }

        It 'reflects the coding intent when supplied' {
            $result = Get-Llamarc42ProjectContextDebug -ProjectFolder $projectDir -Intent coding
            $result.Intent | Should -Be 'coding'
        }

        It 'reflects the review intent when supplied' {
            $result = Get-Llamarc42ProjectContextDebug -ProjectFolder $projectDir -Intent review
            $result.Intent | Should -Be 'review'
        }
    }

    Context 'Resolved paths' {
        It 'returns the resolved ProjectFolder' {
            $result = Get-Llamarc42ProjectContextDebug -ProjectFolder $projectDir
            $result.ProjectFolder | Should -Be $projectDir
        }

        It 'returns the resolved GlobalFolder' {
            $result = Get-Llamarc42ProjectContextDebug -ProjectFolder $projectDir
            $result.GlobalFolder | Should -Be $globalDir
        }

        It 'returns the PolicyPath from the loaded policy' {
            $result = Get-Llamarc42ProjectContextDebug -ProjectFolder $projectDir
            $result.PolicyPath | Should -Be 'fake.yaml'
        }
    }

    Context 'History settings when policy has no history block' {
        It 'returns null for HistoryMaxMessages' {
            $result = Get-Llamarc42ProjectContextDebug -ProjectFolder $projectDir
            $result.HistoryMaxMessages | Should -BeNullOrEmpty
        }

        It 'returns null for HistorySummarizeAfter' {
            $result = Get-Llamarc42ProjectContextDebug -ProjectFolder $projectDir
            $result.HistorySummarizeAfter | Should -BeNullOrEmpty
        }
    }

    Context 'History settings when policy defines a history block' {
        BeforeEach {
            $policyWithHistory = [pscustomobject]@{
                PSTypeName = 'Llamarc42.RetrievalPolicy'
                Path       = 'fake.yaml'
                Policy     = [pscustomobject]@{
                    history = [pscustomobject]@{
                        max_messages    = 20
                        summarize_after = 10
                    }
                }
            }
            Mock Get-Llamarc42RetrievalPolicy -ModuleName llamarc42 { $policyWithHistory }
        }

        It 'returns HistoryMaxMessages from the policy' {
            $result = Get-Llamarc42ProjectContextDebug -ProjectFolder $projectDir
            $result.HistoryMaxMessages | Should -Be 20
        }

        It 'returns HistorySummarizeAfter from the policy' {
            $result = Get-Llamarc42ProjectContextDebug -ProjectFolder $projectDir
            $result.HistorySummarizeAfter | Should -Be 10
        }
    }

    Context 'Files collection' {
        It 'returns an empty Files array when context has no items' {
            $result = Get-Llamarc42ProjectContextDebug -ProjectFolder $projectDir
            $result.Files | Should -HaveCount 0
        }

        It 'maps retrieval context items to file objects with the correct properties' {
            $fakeItem = [pscustomobject]@{
                Scope        = 'project'
                RelativePath = 'spec.md'
                Reason       = 'include'
                Priority     = 1
                OrderRank    = 0
                FullPath     = (Join-Path $projectDir 'spec.md')
            }
            $contextWithItems = [pscustomobject]@{
                PSTypeName    = 'Llamarc42.RetrievalContext'
                PolicyPath    = 'fake.yaml'
                Intent        = 'general'
                ProjectFolder = $projectDir
                GlobalFolder  = $globalDir
                Items         = @($fakeItem)
                Files         = @()
            }
            Mock Resolve-Llamarc42RetrievalContext -ModuleName llamarc42 { $contextWithItems }

            $result = Get-Llamarc42ProjectContextDebug -ProjectFolder $projectDir
            $result.Files | Should -HaveCount 1
            $result.Files[0].Scope        | Should -Be 'project'
            $result.Files[0].RelativePath | Should -Be 'spec.md'
            $result.Files[0].Reason       | Should -Be 'include'
            $result.Files[0].Priority     | Should -Be 1
            $result.Files[0].OrderRank    | Should -Be 0
            $result.Files[0].FullPath     | Should -Be (Join-Path $projectDir 'spec.md')
        }
    }
}
