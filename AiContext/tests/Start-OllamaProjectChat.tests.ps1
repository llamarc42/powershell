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
}

AfterAll {
    Remove-Module AiContext -Force -ErrorAction SilentlyContinue
}

Describe 'Start-OllamaProjectChat' {
    BeforeEach {
        # Mock the interactive/network parts
        Mock Send-OllamaProjectSessionMessage -ModuleName AiContext {
            [pscustomobject]@{
                PSTypeName       = 'Ollama.ProjectSessionChatResult'
                Response         = 'Mocked response'
                UserPrompt       = 'test'
                Intent           = 'general'
                Model            = 'gpt-oss:20b'
                AssistantMessage = [pscustomobject]@{ Content = 'Mocked response' }
            }
        }
        # Mock Read-Host to exit the chat loop immediately
        Mock Read-Host -ModuleName AiContext { ':q' }
    }

    Context 'With -Name matching an existing session' {
        BeforeAll {
            New-TestSessionFolder -SessionId '2026-01-01_120000-myplan' -Name 'myplan' -Title 'My Plan'
        }

        It 'returns an Ollama.ProjectSession object' {
            $result = Start-OllamaProjectChat -ProjectFolder $projectDir -Name 'myplan'
            $result.PSObject.TypeNames[0] | Should -Be 'Ollama.ProjectSession'
        }

        It 'resumes the matching session' {
            $result = Start-OllamaProjectChat -ProjectFolder $projectDir -Name 'myplan'
            $result.Name | Should -Be 'myplan'
        }
    }

    Context 'With -Name that does not match any existing session' {
        BeforeAll {
            # Ensure at least one session exists so Resolve-OllamaProjectSessionByName
            # receives a non-empty array (Mandatory [object[]] rejects empty arrays).
            New-TestSessionFolder -SessionId '2026-01-02_120000-existing' -Name 'existing' -Title 'Existing Session'
        }

        It 'creates a new session with the given name' {
            $result = Start-OllamaProjectChat -ProjectFolder $projectDir -Name 'brand-new-session'
            $result.PSObject.TypeNames[0] | Should -Be 'Ollama.ProjectSession'
            $result.Name | Should -Be 'brand-new-session'
        }
    }

    Context 'Exit commands' {
        BeforeAll {
            New-TestSessionFolder -SessionId '2026-01-01_120000-exitchat' -Name 'exitchat' -Title 'Exit Chat'
        }

        It 'exits when "exit" is typed' {
            Mock Read-Host -ModuleName AiContext { 'exit' }
            { Start-OllamaProjectChat -ProjectFolder $projectDir -Name 'exitchat' } | Should -Not -Throw
        }

        It 'exits when "quit" is typed' {
            Mock Read-Host -ModuleName AiContext { 'quit' }
            { Start-OllamaProjectChat -ProjectFolder $projectDir -Name 'exitchat' } | Should -Not -Throw
        }

        It 'exits when ":q" is typed' {
            Mock Read-Host -ModuleName AiContext { ':q' }
            { Start-OllamaProjectChat -ProjectFolder $projectDir -Name 'exitchat' } | Should -Not -Throw
        }
    }

    Context 'Path resolution' {
        BeforeAll {
            New-TestSessionFolder -SessionId '2026-01-01_120000-pathcheck' -Name 'pathcheck' -Title 'Path Check'
        }

        It 'resolves the project folder correctly' {
            $result = Start-OllamaProjectChat -ProjectFolder $projectDir -Name 'pathcheck'
            $result.ProjectFolder | Should -Be $projectDir
        }
    }
}
