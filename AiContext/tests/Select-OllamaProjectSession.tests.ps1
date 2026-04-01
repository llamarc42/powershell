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

    New-TestSessionFolder -SessionId '2026-01-01_120000-alpha' -Name 'alpha' -Title 'Alpha Chat'
    New-TestSessionFolder -SessionId '2026-02-01_120000-beta'  -Name 'beta'  -Title 'Beta Chat'
}

AfterAll {
    Remove-Module AiContext -Force -ErrorAction SilentlyContinue
}

Describe 'Select-OllamaProjectSession' {
    Context 'When the user selects a valid session' {
        BeforeAll {
            Mock Read-Host -ModuleName AiContext { '1' }
        }

        It 'returns an Ollama.ProjectSession object' {
            $result = Select-OllamaProjectSession -ProjectFolder $projectDir
            $result.PSObject.TypeNames[0] | Should -Be 'Ollama.ProjectSession'
        }

        It 'returns the first session when "1" is entered' {
            $result = Select-OllamaProjectSession -ProjectFolder $projectDir
            # Sessions are sorted newest-first, so index 1 = beta
            $result.Name | Should -Be 'beta'
        }
    }

    Context 'When -AllowNew is used and the user picks the new session option' {
        BeforeAll {
            # There are 2 sessions; "new" is option 3
            Mock Read-Host -ModuleName AiContext { '3' }
        }

        It 'returns $null to signal a new session should be created' {
            $result = Select-OllamaProjectSession -ProjectFolder $projectDir -AllowNew
            $result | Should -BeNullOrEmpty
        }
    }

    Context 'When there are no sessions and -AllowNew is not set' {
        BeforeAll {
            $emptyProj = Join-Path (Join-Path $aiRoot 'projects') 'nosselectproj'
            New-Item -ItemType Directory -Path $emptyProj -Force | Out-Null
        }

        It 'throws an error' {
            { Select-OllamaProjectSession -ProjectFolder $emptyProj } | Should -Throw
        }
    }

    Context 'When there are no sessions and -AllowNew is set' {
        BeforeAll {
            $emptyProj2 = Join-Path (Join-Path $aiRoot 'projects') 'nosselectproj2'
            New-Item -ItemType Directory -Path $emptyProj2 -Force | Out-Null
        }

        It 'returns $null without prompting' {
            $result = Select-OllamaProjectSession -ProjectFolder $emptyProj2 -AllowNew
            $result | Should -BeNullOrEmpty
        }
    }
}
