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

    New-TestSessionFolder -SessionId '2026-01-01_120000-alpha'  -Name 'alpha'  -Title 'Alpha Session'
    New-TestSessionFolder -SessionId '2026-02-01_120000-beta'   -Name 'beta'   -Title 'Beta Session'
    New-TestSessionFolder -SessionId '2026-03-01_120000-review' -Name 'review' -Title 'Review Session'
}

AfterAll {
    Remove-Module AiContext -Force -ErrorAction SilentlyContinue
}

Describe 'Resume-OllamaProjectSession' {
    Context 'No -Name specified' {
        It 'returns the most recent session' {
            $result = Resume-OllamaProjectSession -ProjectFolder $projectDir
            $result.Id | Should -Be '2026-03-01_120000-review'
        }
    }

    Context 'Matching by Name' {
        It 'returns the session matching the name' {
            $result = Resume-OllamaProjectSession -Name 'alpha' -ProjectFolder $projectDir
            $result.Name | Should -Be 'alpha'
        }
    }

    Context 'Matching by Title' {
        It 'returns the session matching a partial title' {
            $result = Resume-OllamaProjectSession -Name 'Beta' -ProjectFolder $projectDir
            $result.Title | Should -Be 'Beta Session'
        }
    }

    Context 'Matching by Id' {
        It 'returns the session matching a partial id' {
            $result = Resume-OllamaProjectSession -Name '2026-03-01' -ProjectFolder $projectDir
            $result.Id | Should -Be '2026-03-01_120000-review'
        }
    }

    Context 'No sessions exist' {
        BeforeAll {
            $emptyProj = Join-Path (Join-Path $aiRoot 'projects') 'nossresumeproj'
            New-Item -ItemType Directory -Path $emptyProj -Force | Out-Null
        }

        It 'throws an error when no sessions are found' {
            { Resume-OllamaProjectSession -ProjectFolder $emptyProj } | Should -Throw
        }
    }

    Context 'Name matches no session' {
        It 'throws an error' {
            { Resume-OllamaProjectSession -Name 'no-such-session' -ProjectFolder $projectDir } |
                Should -Throw
        }
    }

    Context 'Name matches multiple sessions' {
        It 'throws an error listing the ambiguous matches' {
            # "Session" appears in all three titles
            { Resume-OllamaProjectSession -Name 'Session' -ProjectFolder $projectDir } |
                Should -Throw
        }
    }
}
