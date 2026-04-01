BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '..' 'llamarc42.psd1') -Force
}

AfterAll {
    Remove-Module llamarc42 -Force -ErrorAction SilentlyContinue
}

Describe 'Get-Llamarc42Content' {
    BeforeAll {
        $rootPath = Join-Path $TestDrive 'context-root'
        $subDir   = Join-Path $rootPath 'docs'
        New-Item -ItemType Directory -Path $subDir -Force | Out-Null

        $file1 = Join-Path $rootPath 'intro.md'
        $file2 = Join-Path $subDir   'guide.md'
        $file3 = Join-Path $TestDrive 'outside.md'

        Set-Content -Path $file1 -Value 'Introduction content'
        Set-Content -Path $file2 -Value 'Guide content'
        Set-Content -Path $file3 -Value 'Outside content'

        $fileInfo1    = Get-Item $file1
        $fileInfo2    = Get-Item $file2
        $fileInfoOut  = Get-Item $file3
    }

    Context 'Without headers' {
        It 'combines all file contents into one string' {
            $result = Get-Llamarc42Content -Files @($fileInfo1, $fileInfo2) -RootPath $rootPath
            $result | Should -Match 'Introduction content'
            $result | Should -Match 'Guide content'
        }

        It 'returns a non-empty string' {
            $result = Get-Llamarc42Content -Files @($fileInfo1) -RootPath $rootPath
            $result | Should -Not -BeNullOrEmpty
        }

        It 'does not include begin/end file markers' {
            $result = Get-Llamarc42Content -Files @($fileInfo1) -RootPath $rootPath
            $result | Should -Not -Match 'BEGIN FILE'
            $result | Should -Not -Match 'END FILE'
        }
    }

    Context 'With -IncludeHeaders' {
        It 'adds BEGIN FILE and END FILE markers' {
            $result = Get-Llamarc42Content -Files @($fileInfo1) -RootPath $rootPath -IncludeHeaders
            $result | Should -Match 'BEGIN FILE'
            $result | Should -Match 'END FILE'
        }

        It 'includes the relative path in the header' {
            $result = Get-Llamarc42Content -Files @($fileInfo1) -RootPath $rootPath -IncludeHeaders
            $result | Should -Match 'intro\.md'
        }

        It 'includes the nested relative path in the header' {
            $result = Get-Llamarc42Content -Files @($fileInfo2) -RootPath $rootPath -IncludeHeaders
            $result | Should -Match 'docs[/\\]?guide\.md'
        }

        It 'still includes the file content inside the markers' {
            $result = Get-Llamarc42Content -Files @($fileInfo1) -RootPath $rootPath -IncludeHeaders
            $result | Should -Match 'Introduction content'
        }
    }

    Context 'When a file is outside the root path' {
        It 'falls back to the file name in the header' {
            $result = Get-Llamarc42Content -Files @($fileInfoOut) -RootPath $rootPath -IncludeHeaders
            $result | Should -Match 'outside\.md'
        }
    }

    Context 'Return value trimming' {
        It 'returns a trimmed string without leading or trailing whitespace' {
            $result = Get-Llamarc42Content -Files @($fileInfo1) -RootPath $rootPath
            $result | Should -Be $result.Trim()
        }
    }
}
