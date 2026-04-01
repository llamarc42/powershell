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
}

AfterAll {
    Remove-Module llamarc42 -Force -ErrorAction SilentlyContinue
}

Describe 'Get-Llamarc42ProjectContext' {
    Context 'Return object shape' {
        It 'returns an object with the expected properties' {
            $result = Get-Llamarc42ProjectContext -ProjectFolder $projectDir
            $result.PSObject.Properties.Name | Should -Contain 'ProjectFolder'
            $result.PSObject.Properties.Name | Should -Contain 'GlobalFolder'
            $result.PSObject.Properties.Name | Should -Contain 'GlobalFiles'
            $result.PSObject.Properties.Name | Should -Contain 'ProjectFiles'
            $result.PSObject.Properties.Name | Should -Contain 'CombinedContent'
        }

        It 'returns the resolved ProjectFolder path' {
            $result = Get-Llamarc42ProjectContext -ProjectFolder $projectDir
            $result.ProjectFolder | Should -Be $projectDir
        }

        It 'returns the resolved GlobalFolder path' {
            $result = Get-Llamarc42ProjectContext -ProjectFolder $projectDir
            $result.GlobalFolder | Should -Be $globalDir
        }
    }

    Context 'File lists' {
        It 'GlobalFiles contains the global .md file' {
            $result = Get-Llamarc42ProjectContext -ProjectFolder $projectDir
            $result.GlobalFiles | Should -Contain (Join-Path $globalDir 'global-notes.md')
        }

        It 'ProjectFiles contains the project .md file' {
            $result = Get-Llamarc42ProjectContext -ProjectFolder $projectDir
            $result.ProjectFiles | Should -Contain (Join-Path $projectDir 'spec.md')
        }
    }

    Context 'CombinedContent' {
        It 'includes a GLOBAL CONTEXT section' {
            $result = Get-Llamarc42ProjectContext -ProjectFolder $projectDir
            $result.CombinedContent | Should -Match 'GLOBAL CONTEXT'
        }

        It 'includes a PROJECT CONTEXT section' {
            $result = Get-Llamarc42ProjectContext -ProjectFolder $projectDir
            $result.CombinedContent | Should -Match 'PROJECT CONTEXT'
        }

        It 'includes global file content' {
            $result = Get-Llamarc42ProjectContext -ProjectFolder $projectDir
            $result.CombinedContent | Should -Match 'Global notes'
        }

        It 'includes project file content' {
            $result = Get-Llamarc42ProjectContext -ProjectFolder $projectDir
            $result.CombinedContent | Should -Match 'Project spec'
        }
    }

    Context 'With -IncludeFileHeaders' {
        It 'adds file markers to the combined content' {
            $result = Get-Llamarc42ProjectContext -ProjectFolder $projectDir -IncludeFileHeaders
            $result.CombinedContent | Should -Match 'BEGIN FILE'
        }
    }

    Context 'Extension filtering' {
        BeforeAll {
            Set-Content -Path (Join-Path $projectDir 'readme.txt') -Value 'txt file'
        }

        It 'includes .txt files when requested' {
            $result = Get-Llamarc42ProjectContext -ProjectFolder $projectDir -IncludeExtensions '.md', '.txt'
            $result.ProjectFiles | Should -Contain (Join-Path $projectDir 'readme.txt')
        }

        It 'excludes .txt files with default extensions' {
            $result = Get-Llamarc42ProjectContext -ProjectFolder $projectDir -IncludeExtensions '.md'
            $result.ProjectFiles | Should -Not -Contain (Join-Path $projectDir 'readme.txt')
        }
    }
}
