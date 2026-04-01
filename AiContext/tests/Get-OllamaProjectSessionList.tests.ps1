BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '..' 'AiContext.psd1') -Force

    $aiRoot      = Join-Path $TestDrive 'ai'
    $globalDir   = Join-Path $aiRoot 'global'
    $projectsDir = Join-Path $aiRoot 'projects'
    $projectDir  = Join-Path $projectsDir 'myproject'
    $sessionsDir = Join-Path $projectDir '.sessions'

    New-Item -ItemType Directory -Path $globalDir   -Force | Out-Null
    New-Item -ItemType Directory -Path $projectDir  -Force | Out-Null
    New-Item -ItemType Directory -Path $sessionsDir -Force | Out-Null

    function New-TestSessionFolder {
        param(
            [string]$SessionId,
            [string]$Name  = 'chat',
            [string]$Title = 'Chat'
        )
        $folder = Join-Path $sessionsDir $SessionId
        New-Item -ItemType Directory -Path $folder -Force | Out-Null
        New-Item -ItemType File -Path (Join-Path $folder 'messages.jsonl') -Force | Out-Null

        $meta = [ordered]@{
            id                 = $SessionId
            name               = $Name
            title              = $Title
            projectName        = 'myproject'
            projectFolder      = $projectDir
            globalFolder       = $globalDir
            sessionFolder      = $folder
            model              = 'gpt-oss:20b'
            created            = '2026-01-01T12:00:00.0000000+00:00'
            updated            = '2026-01-01T12:00:00.0000000+00:00'
            artifactExtensions = @('.md')
            artifactFiles      = @()
            messageCount       = 0
            rollingSummary     = $null
            tags               = @()
        }
        $meta | ConvertTo-Json -Depth 5 |
            Set-Content -LiteralPath (Join-Path $folder 'session.json')

        return $folder
    }

    New-TestSessionFolder -SessionId '2026-01-01_120000-alpha' -Name 'alpha' -Title 'Alpha Session'
    New-TestSessionFolder -SessionId '2026-02-01_120000-beta'  -Name 'beta'  -Title 'Beta Session'
    New-TestSessionFolder -SessionId '2026-03-01_120000-gamma' -Name 'gamma' -Title 'Gamma Session'
}

AfterAll {
    Remove-Module AiContext -Force -ErrorAction SilentlyContinue
}

Describe 'Get-OllamaProjectSessionList' {
    Context 'Listing all sessions' {
        It 'returns three sessions' {
            $list = Get-OllamaProjectSessionList -ProjectFolder $projectDir
            $list.Count | Should -Be 3
        }

        It 'returns sessions with Ollama.ProjectSessionInfo PSTypeName' {
            $list = Get-OllamaProjectSessionList -ProjectFolder $projectDir
            foreach ($item in $list) {
                $item.PSObject.TypeNames[0] | Should -Be 'Ollama.ProjectSessionInfo'
            }
        }

        It 'returns sessions sorted newest-first' {
            $list = Get-OllamaProjectSessionList -ProjectFolder $projectDir
            $list[0].Id | Should -Be '2026-03-01_120000-gamma'
        }
    }

    Context 'Name filter' {
        It 'returns only sessions matching the Name by Name property' {
            $list = Get-OllamaProjectSessionList -ProjectFolder $projectDir -Name 'beta'
            $list.Count | Should -Be 1
            $list[0].Name | Should -Be 'beta'
        }

        It 'returns only sessions matching the Name by Title property' {
            $list = Get-OllamaProjectSessionList -ProjectFolder $projectDir -Name 'Alpha'
            $list.Count | Should -Be 1
            $list[0].Title | Should -Be 'Alpha Session'
        }

        It 'returns empty array when no session matches' {
            $list = Get-OllamaProjectSessionList -ProjectFolder $projectDir -Name 'no-match'
            $list.Count | Should -Be 0
        }
    }

    Context '-First limit' {
        It 'returns only the first N sessions' {
            $list = Get-OllamaProjectSessionList -ProjectFolder $projectDir -First 2
            $list.Count | Should -Be 2
        }

        It 'returns the newest sessions when First is applied' {
            $list = Get-OllamaProjectSessionList -ProjectFolder $projectDir -First 1
            $list[0].Id | Should -Be '2026-03-01_120000-gamma'
        }
    }

    Context 'When no .sessions folder exists' {
        BeforeAll {
            $emptyProj = Join-Path (Join-Path $aiRoot 'projects') 'emptyproject'
            New-Item -ItemType Directory -Path $emptyProj -Force | Out-Null
        }

        It 'returns an empty array' {
            $list = Get-OllamaProjectSessionList -ProjectFolder $emptyProj
            $list | Should -BeNullOrEmpty
        }
    }

    Context 'Session without session.json' {
        BeforeAll {
            $badFolder = Join-Path $sessionsDir '2026-04-01_120000-corrupt'
            New-Item -ItemType Directory -Path $badFolder -Force | Out-Null
            # No session.json created intentionally
        }

        It 'skips folders with no session.json and returns the rest' {
            $list = Get-OllamaProjectSessionList -ProjectFolder $projectDir
            $list.Id | Should -Not -Contain '2026-04-01_120000-corrupt'
        }
    }
}
