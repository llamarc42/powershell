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

    # Minimal global and project context files (needed for Resolve-RetrievalContext inside send)
    Set-Content -Path (Join-Path $globalDir 'global-notes.md') -Value 'Global notes'
    Set-Content -Path (Join-Path $projectDir 'spec.md')        -Value 'Project spec'

    function New-TestSession {
        param([string]$SessionId = '2026-05-01_120000-sendtest')
        $sessionFolder = Join-Path $sessionsDir $SessionId
        if (Test-Path -LiteralPath $sessionFolder) {
            Remove-Item -LiteralPath $sessionFolder -Recurse -Force
        }
        New-Item -ItemType Directory -Path $sessionFolder -Force | Out-Null
        New-Item -ItemType File -Path (Join-Path $sessionFolder 'messages.jsonl') -Force | Out-Null

        $meta = [ordered]@{
            id                 = $SessionId
            name               = 'sendtest'
            title              = 'Send Test'
            projectName        = 'myproject'
            projectFolder      = $projectDir
            globalFolder       = $globalDir
            sessionFolder      = $sessionFolder
            model              = 'gpt-oss:20b'
            created            = '2026-05-01T12:00:00.0000000+00:00'
            updated            = '2026-05-01T12:00:00.0000000+00:00'
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

    # Fake retrieval objects reused across mocks
    $fakePolicy = [pscustomobject]@{
        PSTypeName = 'Llamarc42.RetrievalPolicy'
        Path       = 'fake.yaml'
        Policy     = @{
            version   = 1
            global    = @{ always_include = @() }
            project   = @{ include = @(); folders = @{} }
            history   = $null
            retrieval = @{ strategies = @{ general = @{ include = @(); max_files = 0 }
                planning = @{ include = @(); max_files = 0 }
                coding   = @{ include = @(); max_files = 0 }
                review   = @{ include = @(); max_files = 0 } } }
        }
    }

    $fakeContext = [pscustomobject]@{
        PSTypeName    = 'Llamarc42.RetrievalContext'
        PolicyPath    = 'fake.yaml'
        Intent        = 'general'
        ProjectFolder = $projectDir
        GlobalFolder  = $globalDir
        Items         = @()
        Files         = @()
    }

    $fakeContent = [pscustomobject]@{
        PSTypeName = 'Llamarc42.RetrievalContextContent'
        Intent     = 'general'
        Files      = @()
        Content    = 'Mocked retrieval content'
        Items      = @()
    }

    $fakeOllamaResponse = [pscustomobject]@{
        model   = 'gpt-oss:20b'
        message = [pscustomobject]@{ role = 'assistant'; content = 'Mocked assistant reply' }
    }
}

AfterAll {
    Remove-Module AiContext -Force -ErrorAction SilentlyContinue
}

Describe 'Send-OllamaProjectSessionMessage' {
    BeforeEach {
        $session = New-TestSession

        Mock Get-RetrievalPolicy        -ModuleName AiContext { $fakePolicy }
        Mock Resolve-RetrievalContext   -ModuleName AiContext { $fakeContext }
        Mock Get-RetrievalContextContent -ModuleName AiContext { $fakeContent }
        Mock Invoke-RestMethod           -ModuleName AiContext { $fakeOllamaResponse }
    }

    Context 'Successful send' {
        It 'returns an Ollama.ProjectSessionChatResult object' {
            $result = Send-OllamaProjectSessionMessage -Session $session -Prompt 'Hello AI'
            $result.PSObject.TypeNames[0] | Should -Be 'Ollama.ProjectSessionChatResult'
        }

        It 'includes the UserPrompt in the result' {
            $result = Send-OllamaProjectSessionMessage -Session $session -Prompt 'Hello AI'
            $result.UserPrompt | Should -Be 'Hello AI'
        }

        It 'includes the assistant response content' {
            $result = Send-OllamaProjectSessionMessage -Session $session -Prompt 'Hello AI'
            $result.Response | Should -Be 'Mocked assistant reply'
        }

        It 'stores both the user and assistant messages in the transcript' {
            Send-OllamaProjectSessionMessage -Session $session -Prompt 'Hello AI' | Out-Null
            $lines = @(Get-Content -LiteralPath $session.MessagesFile | Where-Object { $_ -ne '' })
            $lines.Count | Should -Be 2
            ($lines[0] | ConvertFrom-Json).role | Should -Be 'user'
            ($lines[1] | ConvertFrom-Json).role | Should -Be 'assistant'
        }

        It 'echoes the correct intent in the result' {
            $result = Send-OllamaProjectSessionMessage -Session $session -Prompt 'Hello' -Intent planning
            $result.Intent | Should -Be 'planning'
        }

        It 'uses the session model when no model override is provided' {
            $result = Send-OllamaProjectSessionMessage -Session $session -Prompt 'Hello'
            $result.Model | Should -Be 'gpt-oss:20b'
        }

        It 'uses the override model when -Model is supplied' {
            $result = Send-OllamaProjectSessionMessage -Session $session -Prompt 'Hello' -Model 'llama3:8b'
            $result.Model | Should -Be 'llama3:8b'
        }
    }

    Context 'ConversationWindow in result' {
        It 'includes a ConversationWindow property in the result' {
            $result = Send-OllamaProjectSessionMessage -Session $session -Prompt 'Hello AI'
            $result.PSObject.Properties.Name | Should -Contain 'ConversationWindow'
        }

        It 'ConversationWindow has the Llamarc42.ConversationWindow type' {
            $result = Send-OllamaProjectSessionMessage -Session $session -Prompt 'Hello AI'
            $result.ConversationWindow.PSObject.TypeNames[0] | Should -Be 'Llamarc42.ConversationWindow'
        }
    }

    Context '-RawResponse switch' {
        It 'returns an OllamaResponse property instead of Response' {
            $result = Send-OllamaProjectSessionMessage -Session $session -Prompt 'Hello' -RawResponse
            $result.PSObject.Properties.Name | Should -Contain 'OllamaResponse'
        }

        It 'does not return a Response property when -RawResponse is used' {
            $result = Send-OllamaProjectSessionMessage -Session $session -Prompt 'Hello' -RawResponse
            $result.PSObject.Properties.Name | Should -Not -Contain 'Response'
        }
    }

    Context 'Validation errors' {
        It 'throws when Prompt is empty' {
            { Send-OllamaProjectSessionMessage -Session $session -Prompt '' } | Should -Throw
        }

        It 'throws when Prompt is whitespace' {
            { Send-OllamaProjectSessionMessage -Session $session -Prompt '   ' } | Should -Throw
        }
    }

    Context 'When Ollama returns empty content' {
        BeforeEach {
            Mock Invoke-RestMethod -ModuleName AiContext {
                [pscustomobject]@{ model = 'gpt-oss:20b'; message = [pscustomobject]@{ role = 'assistant'; content = '' } }
            }
        }

        It 'throws an error about missing assistant content' {
            { Send-OllamaProjectSessionMessage -Session $session -Prompt 'Hello' } | Should -Throw
        }
    }

    Context 'ByPath parameter set' {
        It 'accepts a session folder path and returns a result' {
            $result = Send-OllamaProjectSessionMessage -Path $session.SessionFolder -Prompt 'Hello via path'
            $result.PSObject.TypeNames[0] | Should -Be 'Ollama.ProjectSessionChatResult'
        }
    }
}
