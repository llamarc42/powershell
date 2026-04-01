BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '..' 'llamarc42.psd1') -Force
}

AfterAll {
    Remove-Module llamarc42 -Force -ErrorAction SilentlyContinue
}

Describe 'Resolve-Llamarc42Path' {
    BeforeAll {
        $aiRoot      = Join-Path $TestDrive 'ai'
        $globalDir   = Join-Path $aiRoot 'global'
        $projectsDir = Join-Path $aiRoot 'projects'
        $projectDir  = Join-Path $projectsDir 'myproject'

        New-Item -ItemType Directory -Path $globalDir   -Force | Out-Null
        New-Item -ItemType Directory -Path $projectDir  -Force | Out-Null
    }

    Context 'When called with a valid project folder' {
        It 'returns the correct ProjectFolder' {
            $result = Resolve-Llamarc42Path -ProjectFolder $projectDir
            $result.ProjectFolder | Should -Be $projectDir
        }

        It 'returns the correct GlobalFolder' {
            $result = Resolve-Llamarc42Path -ProjectFolder $projectDir
            $result.GlobalFolder | Should -Be $globalDir
        }

        It 'returns the correct AiRoot' {
            $result = Resolve-Llamarc42Path -ProjectFolder $projectDir
            $result.AiRoot | Should -Be $aiRoot
        }

        It 'returns an object with all three expected properties' {
            $result = Resolve-Llamarc42Path -ProjectFolder $projectDir
            $result.PSObject.Properties.Name | Should -Contain 'ProjectFolder'
            $result.PSObject.Properties.Name | Should -Contain 'GlobalFolder'
            $result.PSObject.Properties.Name | Should -Contain 'AiRoot'
        }
    }

    Context 'When called from a child directory inside the project' {
        BeforeAll {
            $childDir = Join-Path $projectDir 'docs' 'subfolder'
            New-Item -ItemType Directory -Path $childDir -Force | Out-Null
        }

        It 'resolves upward to the project root' {
            $result = Resolve-Llamarc42Path -ProjectFolder $childDir
            $result.ProjectFolder | Should -Be $projectDir
        }
    }

    Context 'When an explicit GlobalFolder is supplied' {
        BeforeAll {
            $customGlobal = Join-Path $TestDrive 'custom-global'
            New-Item -ItemType Directory -Path $customGlobal -Force | Out-Null
        }

        It 'uses the provided GlobalFolder instead of the default' {
            $result = Resolve-Llamarc42Path -ProjectFolder $projectDir -GlobalFolder $customGlobal
            $result.GlobalFolder | Should -Be $customGlobal
        }
    }

    Context 'When the path has no ai/projects structure' {
        It 'throws an error' {
            $badPath = Join-Path $TestDrive 'unrelated' 'folder'
            New-Item -ItemType Directory -Path $badPath -Force | Out-Null
            { Resolve-Llamarc42Path -ProjectFolder $badPath } | Should -Throw
        }
    }

    Context 'When the resolved GlobalFolder does not exist' {
        BeforeAll {
            $altAiRoot      = Join-Path $TestDrive 'ai2'
            $altProjectsDir = Join-Path $altAiRoot 'projects'
            $altProjectDir  = Join-Path $altProjectsDir 'noGlobalProject'
            New-Item -ItemType Directory -Path $altProjectDir -Force | Out-Null
            # Intentionally omit ai2/global
        }

        It 'throws an error about the missing global folder' {
            { Resolve-Llamarc42Path -ProjectFolder $altProjectDir } | Should -Throw '*global*'
        }
    }
}
