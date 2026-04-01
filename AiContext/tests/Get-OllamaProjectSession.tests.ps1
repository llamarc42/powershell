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
        $messagesFile = Join-Path $folder 'messages.jsonl'
        New-Item -ItemType File -Path $messagesFile -Force | Out-Null

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

    $sessionId     = '2026-01-01_120000-chat'
    $sessionFolder = New-TestSessionFolder -SessionId $sessionId
}

AfterAll {
    Remove-Module AiContext -Force -ErrorAction SilentlyContinue
}

Describe 'Get-OllamaProjectSession' {
    Context 'Loading by Path' {
        It 'returns an Ollama.ProjectSession object' {
            $result = Get-OllamaProjectSession -Path $sessionFolder
            $result.PSObject.TypeNames[0] | Should -Be 'Ollama.ProjectSession'
        }

        It 'populates the Id property' {
            $result = Get-OllamaProjectSession -Path $sessionFolder
            $result.Id | Should -Be $sessionId
        }

        It 'populates the SessionFolder property' {
            $result = Get-OllamaProjectSession -Path $sessionFolder
            $result.SessionFolder | Should -Be $sessionFolder
        }

        It 'throws when the path does not exist' {
            { Get-OllamaProjectSession -Path (Join-Path $TestDrive 'nonexistent') } |
                Should -Throw
        }

        It 'throws when session.json is missing' {
            $emptyFolder = Join-Path $sessionsDir 'empty-session'
            New-Item -ItemType Directory -Path $emptyFolder -Force | Out-Null
            { Get-OllamaProjectSession -Path $emptyFolder } | Should -Throw
        }
    }

    Context 'Loading by Id' {
        It 'returns the session with the matching Id' {
            $result = Get-OllamaProjectSession -Id $sessionId -ProjectFolder $projectDir
            $result.Id | Should -Be $sessionId
        }

        It 'throws when the Id is not found' {
            { Get-OllamaProjectSession -Id 'nonexistent-id' -ProjectFolder $projectDir } |
                Should -Throw
        }
    }

    Context 'Loading the most recent session (no Id)' {
        BeforeAll {
            # Create a newer session to ensure "most recent" logic is tested
            New-TestSessionFolder -SessionId '2026-06-01_090000-newer'
        }

        It 'returns the most recent session when no Id is specified' {
            $result = Get-OllamaProjectSession -ProjectFolder $projectDir
            $result.Id | Should -Be '2026-06-01_090000-newer'
        }
    }

    Context 'When no .sessions folder exists' {
        BeforeAll {
            $emptyProjDir = Join-Path (Join-Path $aiRoot 'projects') 'nossproject'
            New-Item -ItemType Directory -Path $emptyProjDir -Force | Out-Null
        }

        It 'throws an error' {
            { Get-OllamaProjectSession -ProjectFolder $emptyProjDir } | Should -Throw
        }
    }
}
