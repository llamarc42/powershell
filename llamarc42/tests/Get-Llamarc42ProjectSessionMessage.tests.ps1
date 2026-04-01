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

    $sessionId     = '2026-01-01_120000-chat'
    $sessionFolder = Join-Path $sessionsDir $sessionId
    New-Item -ItemType Directory -Path $sessionFolder -Force | Out-Null

    $messagesFile = Join-Path $sessionFolder 'messages.jsonl'

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

    # Write three messages to the JSONL transcript
    $msg1 = [ordered]@{ role = 'user';      timestamp = '2026-01-01T12:00:00Z'; content = 'Hello' }
    $msg2 = [ordered]@{ role = 'assistant'; timestamp = '2026-01-01T12:00:01Z'; content = 'Hi there' }
    $msg3 = [ordered]@{ role = 'user';      timestamp = '2026-01-01T12:00:02Z'; content = 'How are you?' }

    $lines = @(
        ($msg1 | ConvertTo-Json -Compress),
        ($msg2 | ConvertTo-Json -Compress),
        ($msg3 | ConvertTo-Json -Compress)
    )
    Set-Content -LiteralPath $messagesFile -Value $lines

    $session = Get-Llamarc42ProjectSession -Path $sessionFolder
}

AfterAll {
    Remove-Module llamarc42 -Force -ErrorAction SilentlyContinue
}

Describe 'Get-Llamarc42ProjectSessionMessage' {
    Context 'Reading all messages' {
        It 'returns three messages' {
            $messages = Get-Llamarc42ProjectSessionMessage -Session $session
            $messages.Count | Should -Be 3
        }

        It 'returns objects with PSTypeName Llamarc42.ProjectSessionMessage' {
            $messages = Get-Llamarc42ProjectSessionMessage -Session $session
            foreach ($m in $messages) {
                $m.PSObject.TypeNames[0] | Should -Be 'Llamarc42.ProjectSessionMessage'
            }
        }

        It 'populates the Role property' {
            $messages = Get-Llamarc42ProjectSessionMessage -Session $session
            $messages[0].Role | Should -Be 'user'
            $messages[1].Role | Should -Be 'assistant'
        }

        It 'populates the Content property' {
            $messages = Get-Llamarc42ProjectSessionMessage -Session $session
            $messages[0].Content | Should -Be 'Hello'
            $messages[1].Content | Should -Be 'Hi there'
        }

        It 'populates the SessionId property' {
            $messages = Get-Llamarc42ProjectSessionMessage -Session $session
            $messages[0].SessionId | Should -Be $sessionId
        }
    }

    Context 'With -Tail parameter' {
        It 'returns only the last N messages' {
            $messages = Get-Llamarc42ProjectSessionMessage -Session $session -Tail 2
            $messages.Count | Should -Be 2
            $messages[-1].Content | Should -Be 'How are you?'
        }
    }

    Context 'With -Raw parameter' {
        It 'returns raw deserialized objects without PSTypeName' {
            $messages = Get-Llamarc42ProjectSessionMessage -Session $session -Raw
            foreach ($m in $messages) {
                $m.PSObject.TypeNames[0] | Should -Not -Be 'Llamarc42.ProjectSessionMessage'
            }
        }

        It 'still returns the correct role field on raw objects' {
            $messages = Get-Llamarc42ProjectSessionMessage -Session $session -Raw
            $messages[0].role | Should -Be 'user'
        }
    }

    Context 'By -Path parameter set' {
        It 'returns messages when given a session folder path' {
            $messages = Get-Llamarc42ProjectSessionMessage -Path $sessionFolder
            $messages.Count | Should -Be 3
        }
    }

    Context 'When the messages file does not exist' {
        BeforeAll {
            $badFolder = Join-Path $sessionsDir '2026-99-01_120000-nomsg'
            New-Item -ItemType Directory -Path $badFolder -Force | Out-Null
            $badMeta = [ordered]@{
                id = '2026-99-01_120000-nomsg'; name = 'x'; title = 'X'
                projectName = 'myproject'; projectFolder = $projectDir
                globalFolder = $globalDir; sessionFolder = $badFolder
                model = 'gpt-oss:20b'
                created = '2026-01-01T00:00:00Z'; updated = '2026-01-01T00:00:00Z'
                artifactExtensions = @('.md'); artifactFiles = @()
                messageCount = 0; rollingSummary = $null; tags = @()
            }
            $badMeta | ConvertTo-Json -Depth 5 |
                Set-Content -LiteralPath (Join-Path $badFolder 'session.json')
            # Intentionally omit messages.jsonl
            $badSession = Get-Llamarc42ProjectSession -Path $badFolder
        }

        It 'throws an error' {
            { Get-Llamarc42ProjectSessionMessage -Session $badSession } | Should -Throw
        }
    }

    Context 'When the messages file is empty' {
        BeforeAll {
            $emptyFolder = Join-Path $sessionsDir '2026-98-01_120000-empty'
            New-Item -ItemType Directory -Path $emptyFolder -Force | Out-Null
            New-Item -ItemType File -Path (Join-Path $emptyFolder 'messages.jsonl') -Force | Out-Null
            $emptyMeta = [ordered]@{
                id = '2026-98-01_120000-empty'; name = 'e'; title = 'E'
                projectName = 'myproject'; projectFolder = $projectDir
                globalFolder = $globalDir; sessionFolder = $emptyFolder
                model = 'gpt-oss:20b'
                created = '2026-01-01T00:00:00Z'; updated = '2026-01-01T00:00:00Z'
                artifactExtensions = @('.md'); artifactFiles = @()
                messageCount = 0; rollingSummary = $null; tags = @()
            }
            $emptyMeta | ConvertTo-Json -Depth 5 |
                Set-Content -LiteralPath (Join-Path $emptyFolder 'session.json')
            $emptySession = Get-Llamarc42ProjectSession -Path $emptyFolder
        }

        It 'returns an empty array' {
            $messages = Get-Llamarc42ProjectSessionMessage -Session $emptySession
            $messages.Count | Should -Be 0
        }
    }
}
