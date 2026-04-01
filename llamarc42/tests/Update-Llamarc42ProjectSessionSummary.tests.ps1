BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '..' 'llamarc42.psd1') -Force

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
            [string]$SessionId      = '2026-01-01_120000-sumtest',
            [int]$MessageCount      = 0,
            [string]$RollingSummary = $null,
            [string]$Model          = 'gpt-oss:20b'
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
            name               = 'sumtest'
            title              = 'Summary Test'
            projectName        = 'myproject'
            projectFolder      = $projectDir
            globalFolder       = $globalDir
            sessionFolder      = $sessionFolder
            model              = $Model
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

        return Get-Llamarc42ProjectSession -Path $sessionFolder
    }

    $fakeOllamaSummaryResponse = [pscustomobject]@{
        model   = 'gpt-oss:20b'
        message = [pscustomobject]@{ role = 'assistant'; content = 'Generated rolling summary' }
    }
}

AfterAll {
    Remove-Module llamarc42 -Force -ErrorAction SilentlyContinue
}

Describe 'Update-Llamarc42ProjectSessionSummary' {
    Context 'When no messages need summarizing (short transcript)' {
        BeforeEach {
            # 5 messages, SummarizeAfter 30 -> nothing to summarize
            $session = New-TestSession -SessionId '2026-01-01_120000-sum-short' -MessageCount 5
            Mock Invoke-RestMethod -ModuleName llamarc42 { $fakeOllamaSummaryResponse }
        }

        It 'returns the session object' {
            $result = Update-Llamarc42ProjectSessionSummary -Session $session -SummarizeAfter 30
            $result | Should -Not -BeNull
        }

        It 'returns an object with an Id matching the session' {
            $result = Update-Llamarc42ProjectSessionSummary -Session $session -SummarizeAfter 30
            $result.Id | Should -Be $session.Id
        }

        It 'does not call the Ollama endpoint' {
            Update-Llamarc42ProjectSessionSummary -Session $session -SummarizeAfter 30 | Out-Null
            Should -Invoke Invoke-RestMethod -ModuleName llamarc42 -Times 0
        }
    }

    Context 'When messages need summarizing (long transcript)' {
        BeforeEach {
            # 35 messages; MaxMessages 10, SummarizeAfter 5 -> 25 messages to summarize
            $session = New-TestSession -SessionId '2026-01-01_120000-sum-long' -MessageCount 35
            Mock Invoke-RestMethod -ModuleName llamarc42 { $fakeOllamaSummaryResponse }
        }

        It 'returns the session object' {
            $result = Update-Llamarc42ProjectSessionSummary -Session $session -MaxMessages 10 -SummarizeAfter 5
            $result | Should -Not -BeNull
        }

        It 'calls the Ollama endpoint once' {
            Update-Llamarc42ProjectSessionSummary -Session $session -MaxMessages 10 -SummarizeAfter 5 | Out-Null
            Should -Invoke Invoke-RestMethod -ModuleName llamarc42 -Times 1
        }

        It 'updates the RollingSummary on the returned session' {
            $result = Update-Llamarc42ProjectSessionSummary -Session $session -MaxMessages 10 -SummarizeAfter 5
            $result.RollingSummary | Should -Be 'Generated rolling summary'
        }

        It 'persists the updated RollingSummary to disk' {
            Update-Llamarc42ProjectSessionSummary -Session $session -MaxMessages 10 -SummarizeAfter 5 | Out-Null
            $persisted = Get-Llamarc42ProjectSession -Path $session.SessionFolder
            $persisted.RollingSummary | Should -Be 'Generated rolling summary'
        }

        It 'updates the Updated timestamp on disk' {
            $before = $session.Updated
            Update-Llamarc42ProjectSessionSummary -Session $session -MaxMessages 10 -SummarizeAfter 5 | Out-Null
            $persisted = Get-Llamarc42ProjectSession -Path $session.SessionFolder
            $persisted.Updated | Should -Not -Be $before
        }
    }

    Context 'Model selection' {
        BeforeEach {
            $session = New-TestSession -SessionId '2026-01-01_120000-sum-model' -MessageCount 35
        }

        It 'uses the session model when no -Model override is provided' {
            $script:capturedBody = $null
            Mock Invoke-RestMethod -ModuleName llamarc42 {
                $script:capturedBody = ($Body | ConvertFrom-Json)
                $fakeOllamaSummaryResponse
            }
            Update-Llamarc42ProjectSessionSummary -Session $session -MaxMessages 10 -SummarizeAfter 5 | Out-Null
            $script:capturedBody.model | Should -Be 'gpt-oss:20b'
        }

        It 'uses the -Model override when provided' {
            $script:capturedBody = $null
            Mock Invoke-RestMethod -ModuleName llamarc42 {
                $script:capturedBody = ($Body | ConvertFrom-Json)
                $fakeOllamaSummaryResponse
            }
            Update-Llamarc42ProjectSessionSummary -Session $session -MaxMessages 10 -SummarizeAfter 5 -Model 'llama3:8b' | Out-Null
            $script:capturedBody.model | Should -Be 'llama3:8b'
        }
    }

    Context 'Error handling' {
        BeforeEach {
            $session = New-TestSession -SessionId '2026-01-01_120000-sum-err' -MessageCount 35
        }

        It 'throws when the Ollama endpoint call fails' {
            Mock Invoke-RestMethod -ModuleName llamarc42 { throw 'Connection refused' }
            { Update-Llamarc42ProjectSessionSummary -Session $session -MaxMessages 10 -SummarizeAfter 5 } |
                Should -Throw
        }

        It 'throws when Ollama returns empty summary content' {
            Mock Invoke-RestMethod -ModuleName llamarc42 {
                [pscustomobject]@{
                    model   = 'gpt-oss:20b'
                    message = [pscustomobject]@{ role = 'assistant'; content = '' }
                }
            }
            { Update-Llamarc42ProjectSessionSummary -Session $session -MaxMessages 10 -SummarizeAfter 5 } |
                Should -Throw
        }
    }

    Context 'ByPath parameter set' {
        BeforeEach {
            $session = New-TestSession -SessionId '2026-01-01_120000-sum-path' -MessageCount 5
            Mock Invoke-RestMethod -ModuleName llamarc42 { $fakeOllamaSummaryResponse }
        }

        It 'accepts a session folder path and returns the session' {
            $result = Update-Llamarc42ProjectSessionSummary -Path $session.SessionFolder -SummarizeAfter 30
            $result | Should -Not -BeNull
        }
    }

    Context 'Pipeline input' {
        BeforeEach {
            $session = New-TestSession -SessionId '2026-01-01_120000-sum-pipe' -MessageCount 5
            Mock Invoke-RestMethod -ModuleName llamarc42 { $fakeOllamaSummaryResponse }
        }

        It 'accepts a session object via the pipeline' {
            $result = $session | Update-Llamarc42ProjectSessionSummary -SummarizeAfter 30
            $result | Should -Not -BeNull
        }
    }
}
