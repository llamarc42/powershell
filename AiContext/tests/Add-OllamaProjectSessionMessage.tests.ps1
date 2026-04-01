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

    function New-TestSession {
        $sessionId     = '2026-01-01_120000-chat'
        $sessionFolder = Join-Path $sessionsDir $sessionId
        New-Item -ItemType Directory -Path $sessionFolder -Force | Out-Null
        $messagesFile = Join-Path $sessionFolder 'messages.jsonl'
        New-Item -ItemType File -Path $messagesFile -Force | Out-Null

        $meta = [ordered]@{
            id                 = $sessionId
            name               = 'chat'
            title              = 'Chat'
            projectName        = 'myproject'
            projectFolder      = $projectDir
            globalFolder       = $globalDir
            sessionFolder      = $sessionFolder
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
            Set-Content -LiteralPath (Join-Path $sessionFolder 'session.json')

        return Get-OllamaProjectSession -Path $sessionFolder
    }
}

AfterAll {
    Remove-Module AiContext -Force -ErrorAction SilentlyContinue
}

Describe 'Add-OllamaProjectSessionMessage' {
    BeforeEach {
        # Start fresh with an empty session for each test
        Remove-Item -LiteralPath (Join-Path $sessionsDir '2026-01-01_120000-chat') -Recurse -Force -ErrorAction SilentlyContinue
        $session = New-TestSession
    }

    Context 'Return value' {
        It 'returns an Ollama.ProjectSessionMessage object' {
            $result = Add-OllamaProjectSessionMessage -Session $session -Role user -Content 'Hello'
            $result.PSObject.TypeNames[0] | Should -Be 'Ollama.ProjectSessionMessage'
        }

        It 'returns the correct Role' {
            $result = Add-OllamaProjectSessionMessage -Session $session -Role assistant -Content 'Hi'
            $result.Role | Should -Be 'assistant'
        }

        It 'returns the correct Content' {
            $result = Add-OllamaProjectSessionMessage -Session $session -Role user -Content 'Test message'
            $result.Content | Should -Be 'Test message'
        }

        It 'returns the correct SessionId' {
            $result = Add-OllamaProjectSessionMessage -Session $session -Role user -Content 'Hello'
            $result.SessionId | Should -Be $session.Id
        }

        It 'returns a non-empty Timestamp' {
            $result = Add-OllamaProjectSessionMessage -Session $session -Role user -Content 'Hello'
            $result.Timestamp | Should -Not -BeNullOrEmpty
        }
    }

    Context 'File persistence' {
        It 'appends a line to messages.jsonl' {
            Add-OllamaProjectSessionMessage -Session $session -Role user -Content 'First' | Out-Null
            $lines = @(Get-Content -LiteralPath $session.MessagesFile | Where-Object { $_ -ne '' })
            $lines.Count | Should -Be 1
        }

        It 'appends multiple messages in order' {
            Add-OllamaProjectSessionMessage -Session $session -Role user      -Content 'First'  | Out-Null
            Add-OllamaProjectSessionMessage -Session $session -Role assistant -Content 'Second' | Out-Null
            $lines = @(Get-Content -LiteralPath $session.MessagesFile | Where-Object { $_ -ne '' })
            $lines.Count | Should -Be 2
            ($lines[0] | ConvertFrom-Json).content | Should -Be 'First'
            ($lines[1] | ConvertFrom-Json).content | Should -Be 'Second'
        }

        It 'writes valid JSON for each line' {
            Add-OllamaProjectSessionMessage -Session $session -Role system -Content 'System init' | Out-Null
            $lines = @(Get-Content -LiteralPath $session.MessagesFile | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
            { $lines[0] | ConvertFrom-Json } | Should -Not -Throw
        }
    }

    Context 'Metadata update' {
        It 'increments the MessageCount in the session metadata' {
            Add-OllamaProjectSessionMessage -Session $session -Role user -Content 'Hello' | Out-Null
            $updated = Get-OllamaProjectSession -Path $session.SessionFolder
            $updated.MessageCount | Should -Be 1
        }

        It 'updates the Updated timestamp in the session metadata' {
            $before = $session.Updated
            Add-OllamaProjectSessionMessage -Session $session -Role user -Content 'Hello' | Out-Null
            $updated = Get-OllamaProjectSession -Path $session.SessionFolder
            $updated.Updated | Should -Not -Be $before
        }
    }

    Context 'All supported roles' {
        It 'accepts role "user"' {
            { Add-OllamaProjectSessionMessage -Session $session -Role user -Content 'x' } |
                Should -Not -Throw
        }

        It 'accepts role "assistant"' {
            { Add-OllamaProjectSessionMessage -Session $session -Role assistant -Content 'x' } |
                Should -Not -Throw
        }

        It 'accepts role "system"' {
            { Add-OllamaProjectSessionMessage -Session $session -Role system -Content 'x' } |
                Should -Not -Throw
        }
    }

    Context 'Validation errors' {
        It 'throws when Content is empty' {
            { Add-OllamaProjectSessionMessage -Session $session -Role user -Content '' } |
                Should -Throw
        }

        It 'throws when Content is whitespace only' {
            { Add-OllamaProjectSessionMessage -Session $session -Role user -Content '   ' } |
                Should -Throw
        }
    }

    Context 'ByPath parameter set' {
        It 'appends a message when given a session folder path' {
            Add-OllamaProjectSessionMessage -Path $session.SessionFolder -Role user -Content 'Via path' | Out-Null
            $lines = @(Get-Content -LiteralPath $session.MessagesFile | Where-Object { $_ -ne '' })
            $lines.Count | Should -Be 1
        }
    }
}
