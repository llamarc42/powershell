BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '..' 'AiContext.psd1') -Force
}

AfterAll {
    Remove-Module AiContext -Force -ErrorAction SilentlyContinue
}

Describe 'Get-AiContextFiles' {
    BeforeAll {
        $scanRoot = Join-Path $TestDrive 'scan'
        $subDir   = Join-Path $scanRoot 'sub'
        New-Item -ItemType Directory -Path $subDir -Force | Out-Null

        Set-Content -Path (Join-Path $scanRoot 'readme.md')   -Value 'md content'
        Set-Content -Path (Join-Path $scanRoot 'notes.txt')   -Value 'txt content'
        Set-Content -Path (Join-Path $scanRoot 'script.ps1')  -Value 'ps1 content'
        Set-Content -Path (Join-Path $subDir   'nested.md')   -Value 'nested md'
        Set-Content -Path (Join-Path $subDir   'data.json')   -Value '{}'
    }

    Context 'Default extension filtering (.md and .txt)' {
        It 'returns .md files' {
            $files = Get-AiContextFiles -Path $scanRoot
            $files.Name | Should -Contain 'readme.md'
        }

        It 'returns .txt files' {
            $files = Get-AiContextFiles -Path $scanRoot
            $files.Name | Should -Contain 'notes.txt'
        }

        It 'excludes files with non-matching extensions' {
            $files = Get-AiContextFiles -Path $scanRoot
            $files.Name | Should -Not -Contain 'script.ps1'
            $files.Name | Should -Not -Contain 'data.json'
        }
    }

    Context 'Recursive scanning' {
        It 'returns files in subdirectories' {
            $files = Get-AiContextFiles -Path $scanRoot
            $files.Name | Should -Contain 'nested.md'
        }
    }

    Context 'Custom extension filtering' {
        It 'returns only files with the specified extension' {
            $files = Get-AiContextFiles -Path $scanRoot -IncludeExtensions '.ps1'
            $files.Name | Should -Contain 'script.ps1'
            $files.Name | Should -Not -Contain 'readme.md'
        }

        It 'accepts extensions without a leading dot' {
            $files = Get-AiContextFiles -Path $scanRoot -IncludeExtensions 'md'
            $files.Name | Should -Contain 'readme.md'
            $files.Name | Should -Contain 'nested.md'
        }

        It 'accepts a mix of extensions with and without leading dots' {
            $files = Get-AiContextFiles -Path $scanRoot -IncludeExtensions 'md', '.json'
            $files.Name | Should -Contain 'readme.md'
            $files.Name | Should -Contain 'data.json'
        }
    }

    Context 'Sorting' {
        It 'returns files sorted by full path' {
            $files = Get-AiContextFiles -Path $scanRoot
            $sorted = $files | Sort-Object FullName
            $files.FullName | Should -Be $sorted.FullName
        }
    }

    Context 'When no files match' {
        It 'returns an empty result' {
            $files = Get-AiContextFiles -Path $scanRoot -IncludeExtensions '.xyz'
            @($files).Count | Should -Be 0
        }
    }

    Context 'Return type' {
        It 'returns System.IO.FileInfo objects' {
            $files = Get-AiContextFiles -Path $scanRoot
            foreach ($f in $files) {
                $f | Should -BeOfType [System.IO.FileInfo]
            }
        }
    }
}
