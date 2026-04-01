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
        param(
            [string]$SessionId    = '2026-01-01_120000-wintest',
            [int]$MessageCount    = 0,
            [string]$RollingSummary = $null
        )

        $sessionFolder = Join-Path $sessionsDir $SessionId
        if (Test-Path -LiteralPath $sessionFolder) {
            Remove-Item -LiteralPath $sessionFolder -Recurse -Force
        }
        New-Item -ItemType Directory -Path $sessionFolder -Force | Out-Null
        $messagesFile = Join-Path $sessionFolder 'messages.jsonl'
        New-Item -ItemType File -Path $messagesFile -Force | Out-Null

        $lines = for ($i = 0; $i -lt $MessageCount; $i++) {
            $role = if ($i % 2 -eq 0) { 'user' } else { 'assistant' }
            $ts   = '2026-01-01T12:{0:D2}:{1:D2}Z' -f [int]($i / 60), ($i % 60)
            [ordered]@{ role = $role; timestamp = $ts; content = "Message $i" } | ConvertTo-Json -Compress
        }
        if ($lines) {
            Set-Content -LiteralPath $messagesFile -Value $lines
        }

        $meta = [ordered]@{
            id                 = $SessionId
            name               = 'wintest'
            title              = 'Window Test'
            projectName        = 'myproject'
            projectFolder      = $projectDir
            globalFolder       = $globalDir
            sessionFolder      = $sessionFolder
            model              = 'gpt-oss:20b'
            created            = '2026-01-01T12:00:00.0000000+00:00'
            updated            = '2026-01-01T12:00:00.0000000+00:00'
            artifactExtensions = @('.md')
            artifactFiles      = @()
            messageCount       = $MessageCount
            rollingSummary     = $RollingSummary
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

Describe 'Get-OllamaProjectSessionConversationWindow' {
    Context 'Return value shape' {
        It 'returns a Llamarc42.ConversationWindow object' {
            $session = New-TestSession -SessionId '2026-01-01_120000-win-type' -MessageCount 3
            $result  = Get-OllamaProjectSessionConversationWindow -Session $session
            $result.PSObject.TypeNames[0] | Should -Be 'Llamarc42.ConversationWindow'
        }

        It 'populates the Session property' {
            $session = New-TestSession -SessionId '2026-01-01_120000-win-sess' -MessageCount 3
            $result  = Get-OllamaProjectSessionConversationWindow -Session $session
            $result.Session | Should -Not -BeNull
        }

        It 'reflects the correct TotalMessageCount' {
            $session = New-TestSession -SessionId '2026-01-01_120000-win-total' -MessageCount 7
            $result  = Get-OllamaProjectSessionConversationWindow -Session $session
            $result.TotalMessageCount | Should -Be 7
        }

        It 'reflects the MaxMessages parameter in the result' {
            $session = New-TestSession -SessionId '2026-01-01_120000-win-max' -MessageCount 2
            $result  = Get-OllamaProjectSessionConversationWindow -Session $session -MaxMessages 20
            $result.MaxMessages | Should -Be 20
        }

        It 'reflects the SummarizeAfter parameter in the result' {
            $session = New-TestSession -SessionId '2026-01-01_120000-win-sumafter' -MessageCount 2
            $result  = Get-OllamaProjectSessionConversationWindow -Session $session -SummarizeAfter 10
            $result.SummarizeAfter | Should -Be 10
        }
    }

    Context 'When transcript is within the SummarizeAfter threshold' {
        BeforeAll {
            $session = New-TestSession -SessionId '2026-01-01_120000-win-short' -MessageCount 5
        }

        It 'returns all messages in RecentMessages' {
            $result = Get-OllamaProjectSessionConversationWindow -Session $session -SummarizeAfter 30
            $result.RecentMessages.Count | Should -Be 5
        }

        It 'returns an empty MessagesToSummarize array' {
            $result = Get-OllamaProjectSessionConversationWindow -Session $session -SummarizeAfter 30
            $result.MessagesToSummarize.Count | Should -Be 0
        }
    }

    Context 'When transcript exceeds the SummarizeAfter threshold and MaxMessages is less than total' {
        BeforeAll {
            # 35 messages; MaxMessages 10, SummarizeAfter 5 -> 10 recent, 25 to summarize
            $session = New-TestSession -SessionId '2026-01-01_120000-win-long' -MessageCount 35
        }

        It 'keeps at most MaxMessages in RecentMessages' {
            $result = Get-OllamaProjectSessionConversationWindow -Session $session -MaxMessages 10 -SummarizeAfter 5
            $result.RecentMessages.Count | Should -Be 10
        }

        It 'assigns older messages to MessagesToSummarize' {
            $result = Get-OllamaProjectSessionConversationWindow -Session $session -MaxMessages 10 -SummarizeAfter 5
            $result.MessagesToSummarize.Count | Should -Be 25
        }

        It 'total of RecentMessages and MessagesToSummarize equals TotalMessageCount' {
            $result = Get-OllamaProjectSessionConversationWindow -Session $session -MaxMessages 10 -SummarizeAfter 5
            ($result.RecentMessages.Count + $result.MessagesToSummarize.Count) | Should -Be $result.TotalMessageCount
        }

        It 'RecentMessages contains only the most recent messages' {
            $result = Get-OllamaProjectSessionConversationWindow -Session $session -MaxMessages 10 -SummarizeAfter 5
            $result.RecentMessages[-1].Content | Should -Be 'Message 34'
        }
    }

    Context 'RollingSummary' {
        It 'returns a null RollingSummary when the session has no summary' {
            $session = New-TestSession -SessionId '2026-01-01_120000-win-nosumm' -MessageCount 2
            $result  = Get-OllamaProjectSessionConversationWindow -Session $session
            $result.RollingSummary | Should -BeNullOrEmpty
        }

        It 'returns the existing RollingSummary from the session' {
            $session = New-TestSession -SessionId '2026-01-01_120000-win-summ' -MessageCount 2 -RollingSummary 'Prior summary text'
            $result  = Get-OllamaProjectSessionConversationWindow -Session $session
            $result.RollingSummary | Should -Be 'Prior summary text'
        }
    }

    Context 'ByPath parameter set' {
        It 'accepts a session folder path and returns a ConversationWindow' {
            $session = New-TestSession -SessionId '2026-01-01_120000-win-path' -MessageCount 3
            $result  = Get-OllamaProjectSessionConversationWindow -Path $session.SessionFolder
            $result.PSObject.TypeNames[0] | Should -Be 'Llamarc42.ConversationWindow'
        }
    }

    Context 'Pipeline input' {
        It 'accepts a session object via the pipeline' {
            $session = New-TestSession -SessionId '2026-01-01_120000-win-pipe' -MessageCount 3
            $result  = $session | Get-OllamaProjectSessionConversationWindow
            $result.PSObject.TypeNames[0] | Should -Be 'Llamarc42.ConversationWindow'
        }
    }
}
