BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '..' 'AiContext.psd1') -Force

    $aiRoot      = Join-Path $TestDrive 'ai'
    $globalDir   = Join-Path $aiRoot 'global'
    $projectsDir = Join-Path $aiRoot 'projects'
    $projectDir  = Join-Path $projectsDir 'myproject'

    New-Item -ItemType Directory -Path $globalDir  -Force | Out-Null
    New-Item -ItemType Directory -Path $projectDir -Force | Out-Null
}

AfterAll {
    Remove-Module AiContext -Force -ErrorAction SilentlyContinue
}

Describe 'New-OllamaProjectSession' {
    Context 'Default parameters' {
        BeforeAll {
            $session = New-OllamaProjectSession -ProjectFolder $projectDir
        }

        It 'returns an Ollama.ProjectSession object' {
            $session.PSObject.TypeNames[0] | Should -Be 'Ollama.ProjectSession'
        }

        It 'uses "chat" as the default name' {
            $session.Name | Should -Be 'chat'
        }

        It 'uses the default model' {
            $session.Model | Should -Be 'gpt-oss:20b'
        }

        It 'sets MessageCount to 0' {
            $session.MessageCount | Should -Be 0
        }

        It 'creates a session folder on disk' {
            Test-Path -LiteralPath $session.SessionFolder -PathType Container | Should -BeTrue
        }

        It 'creates a session.json file' {
            Test-Path -LiteralPath $session.SessionFile -PathType Leaf | Should -BeTrue
        }

        It 'creates a messages.jsonl file' {
            Test-Path -LiteralPath $session.MessagesFile -PathType Leaf | Should -BeTrue
        }

        It 'stores the correct ProjectFolder' {
            $session.ProjectFolder | Should -Be $projectDir
        }

        It 'stores the correct GlobalFolder' {
            $session.GlobalFolder | Should -Be $globalDir
        }
    }

    Context 'Custom name and title' {
        It 'slugifies the Name into the session id' {
            $s = New-OllamaProjectSession -Name 'API Review' -ProjectFolder $projectDir
            $s.Name | Should -Be 'api-review'
        }

        It 'uses the provided Title' {
            $s = New-OllamaProjectSession -Name 'my-session' -Title 'My Custom Title' -ProjectFolder $projectDir
            $s.Title | Should -Be 'My Custom Title'
        }

        It 'auto-generates a Title from the slug when Title is omitted' {
            $s = New-OllamaProjectSession -Name 'hello-world' -ProjectFolder $projectDir
            $s.Title | Should -Be 'Hello World'
        }
    }

    Context 'Custom model' {
        It 'stores the specified model' {
            $s = New-OllamaProjectSession -Model 'llama3:8b' -ProjectFolder $projectDir
            $s.Model | Should -Be 'llama3:8b'
        }
    }

    Context 'Tags and extensions' {
        It 'stores the provided tags' {
            $s = New-OllamaProjectSession -Tags @('ci', 'review') -ProjectFolder $projectDir
            $s.Tags | Should -Contain 'ci'
            $s.Tags | Should -Contain 'review'
        }

        It 'stores the provided ArtifactExtensions' {
            $s = New-OllamaProjectSession -Name 'test-extensions' -ArtifactExtensions @('.md', '.txt') -ProjectFolder $projectDir
            $s.ArtifactExtensions | Should -Contain '.md'
            $s.ArtifactExtensions | Should -Contain '.txt'
        }
    }

    Context 'When the session folder already exists' {
        It 'throws an error' {
            # Create a session then try to create another with the same id
            $s = New-OllamaProjectSession -Name 'duplicate-test' -ProjectFolder $projectDir
            # Directly re-create the folder to simulate the collision scenario
            New-Item -ItemType Directory -Path $s.SessionFolder -Force | Out-Null
            { New-OllamaProjectSession -Name 'duplicate-test' -ProjectFolder $projectDir } |
                Should -Throw
        }
    }
}
