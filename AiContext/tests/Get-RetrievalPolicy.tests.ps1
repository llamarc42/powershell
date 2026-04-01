BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '..' 'AiContext.psd1') -Force

    # Build minimal ai folder structure
    $aiRoot      = Join-Path $TestDrive 'ai'
    $globalDir   = Join-Path $aiRoot 'global'
    $projectsDir = Join-Path $aiRoot 'projects'
    $projectDir  = Join-Path $projectsDir 'myproject'
    $toolingDir  = Join-Path $aiRoot 'tooling' 'config'

    New-Item -ItemType Directory -Path $globalDir   -Force | Out-Null
    New-Item -ItemType Directory -Path $projectDir  -Force | Out-Null
    New-Item -ItemType Directory -Path $toolingDir  -Force | Out-Null

    $policyFile = Join-Path $toolingDir 'retrieval.yaml'
    Set-Content -Path $policyFile -Value 'version: 1'

    # Create a global stub for ConvertFrom-Yaml so Pester can mock it in tests that
    # need to simulate the powershell-yaml module being present.
    $script:createdConvertFromYamlStub = $false
    if (-not (Get-Command ConvertFrom-Yaml -ErrorAction SilentlyContinue)) {
        $script:createdConvertFromYamlStub = $true
        Set-Item -Path Function:global:ConvertFrom-Yaml -Value {
            param([Parameter(ValueFromPipeline)] $InputObject)
            process { }
        }
    }
}

AfterAll {
    Remove-Module AiContext -Force -ErrorAction SilentlyContinue
    if ($script:createdConvertFromYamlStub) {
        Remove-Item -Path Function:global:ConvertFrom-Yaml -ErrorAction SilentlyContinue
    }
}

Describe 'Get-RetrievalPolicy' {
    Context 'When ConvertFrom-Yaml is not available' {
        It 'throws an error referencing powershell-yaml' {
            # This context relies on the real absence of the powershell-yaml module.
            # The stub created in BeforeAll is global but the module's Get-Command check
            # runs in its own scope; the mock below ensures it reports "not found".
            Mock Get-Command -ModuleName AiContext -ParameterFilter { $Name -eq 'ConvertFrom-Yaml' } {
                $null
            }
            { Get-RetrievalPolicy -ProjectFolder $projectDir } |
                Should -Throw "*powershell-yaml*"
        }
    }

    Context 'When the policy file does not exist' {
        BeforeAll {
            $altToolingDir = Join-Path $aiRoot 'tooling2' 'config'
            New-Item -ItemType Directory -Path $altToolingDir -Force | Out-Null

            Mock Get-Command -ModuleName AiContext -ParameterFilter { $Name -eq 'ConvertFrom-Yaml' } {
                [pscustomobject]@{ Name = 'ConvertFrom-Yaml' }
            }
        }

        It 'throws an error about the missing file' {
            $missingPolicyPath = Join-Path $aiRoot 'tooling2' 'config' 'retrieval.yaml'
            { Get-RetrievalPolicy -ProjectFolder $projectDir -PolicyPath $missingPolicyPath } |
                Should -Throw "*not found*"
        }
    }

    Context 'When ConvertFrom-Yaml is available and returns a valid policy' {
        BeforeAll {
            Mock Get-Command -ModuleName AiContext -ParameterFilter { $Name -eq 'ConvertFrom-Yaml' } {
                [pscustomobject]@{ Name = 'ConvertFrom-Yaml' }
            }

            Mock ConvertFrom-Yaml -ModuleName AiContext {
                @{
                    version   = 1
                    global    = @{ always_include = @() }
                    project   = @{ include = @(); folders = @{} }
                    retrieval = @{ strategies = @{} }
                }
            }
        }

        It 'returns an object with PSTypeName Llamarc42.RetrievalPolicy' {
            $result = Get-RetrievalPolicy -ProjectFolder $projectDir
            $result.PSObject.TypeNames[0] | Should -Be 'Llamarc42.RetrievalPolicy'
        }

        It 'returns an object with a Path property' {
            $result = Get-RetrievalPolicy -ProjectFolder $projectDir
            $result.Path | Should -Not -BeNullOrEmpty
        }

        It 'returns an object with a Policy property' {
            $result = Get-RetrievalPolicy -ProjectFolder $projectDir
            $result.Policy | Should -Not -BeNullOrEmpty
        }
    }

    Context 'When the parsed policy is missing required sections' {
        BeforeAll {
            Mock Get-Command -ModuleName AiContext -ParameterFilter { $Name -eq 'ConvertFrom-Yaml' } {
                [pscustomobject]@{ Name = 'ConvertFrom-Yaml' }
            }
        }

        It 'throws when version is missing' {
            Mock ConvertFrom-Yaml -ModuleName AiContext {
                @{ global = @{}; project = @{}; retrieval = @{} }
            }
            { Get-RetrievalPolicy -ProjectFolder $projectDir } | Should -Throw '*version*'
        }

        It 'throws when global section is missing' {
            Mock ConvertFrom-Yaml -ModuleName AiContext {
                @{ version = 1; project = @{}; retrieval = @{} }
            }
            { Get-RetrievalPolicy -ProjectFolder $projectDir } | Should -Throw '*global*'
        }

        It 'throws when project section is missing' {
            Mock ConvertFrom-Yaml -ModuleName AiContext {
                @{ version = 1; global = @{}; retrieval = @{} }
            }
            { Get-RetrievalPolicy -ProjectFolder $projectDir } | Should -Throw '*project*'
        }

        It 'throws when retrieval section is missing' {
            Mock ConvertFrom-Yaml -ModuleName AiContext {
                @{ version = 1; global = @{}; project = @{} }
            }
            { Get-RetrievalPolicy -ProjectFolder $projectDir } | Should -Throw '*retrieval*'
        }
    }
}
