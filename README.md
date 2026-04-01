# AiContext PowerShell Module

A PowerShell module for **architecture-aware, file-based retrieval over local project documentation**, backed by a locally running [Ollama](https://ollama.com) instance.

`AiContext` walks your `ai/projects/<project>` workspace, applies a declarative retrieval policy, and sends **grounded*- prompts to Ollama for either:

- persistent, resumable chat sessions, or
- programmatic session-based queries

> AiContext does **not*- fine-tune or train the model. It retrieves documentation artifacts at runtime and sends only the selected context to Ollama for each request.

---

## Table of Contents

- [AiContext PowerShell Module](#aicontext-powershell-module)
  - [Table of Contents](#table-of-contents)
  - [Overview](#overview)
  - [What AiContext Solves](#what-aicontext-solves)
  - [How It Works](#how-it-works)
  - [Folder Convention](#folder-convention)
  - [Requirements](#requirements)
  - [Installation](#installation)
  - [Quick Start](#quick-start)
    - [Start an interactive architecture-aware chat](#start-an-interactive-architecture-aware-chat)
    - [Resume a prior session and continue it](#resume-a-prior-session-and-continue-it)
    - [Inspect retrieved context before sending anything](#inspect-retrieved-context-before-sending-anything)
    - [Inspect the exact prompt without calling Ollama](#inspect-the-exact-prompt-without-calling-ollama)
  - [Retrieval Policy](#retrieval-policy)
    - [Selection order](#selection-order)
  - [Working Examples](#working-examples)
    - [Example 1: Architecture planning](#example-1-architecture-planning)
    - [Example 2: Design review / drift check](#example-2-design-review--drift-check)
    - [Example 3: Session continuity over time](#example-3-session-continuity-over-time)
    - [Example 4: Programmatic use in scripts](#example-4-programmatic-use-in-scripts)
  - [Session Storage](#session-storage)
  - [Module Reference](#module-reference)
    - [Path \& File Resolution](#path--file-resolution)
    - [Retrieval Policy \& Context](#retrieval-policy--context)
    - [Session Management](#session-management)
    - [Conversation Scaling \& Summarization](#conversation-scaling--summarization)
    - [Chat \& Interaction](#chat--interaction)
    - [Diagnostics](#diagnostics)
  - [Repository Layout](#repository-layout)
  - [Design Notes](#design-notes)
  - [Troubleshooting](#troubleshooting)
    - [`ConvertFrom-Yaml` is not available](#convertfrom-yaml-is-not-available)
    - [Ollama connection failed](#ollama-connection-failed)
    - [Project path could not be resolved](#project-path-could-not-be-resolved)
    - [Retrieval policy not found](#retrieval-policy-not-found)
    - [No assistant message content was returned](#no-assistant-message-content-was-returned)
  - [License](#license)

---

## Overview

`AiContext` solves a common problem when working with local AI models:

> How do you reliably feed the model the **right*- subset of project documentation without copying and pasting files by hand?

The module provides:

| Capability | Description |
| --- | --- |
| **Path resolution*- | Automatically discovers the `ai/` workspace root by walking upward from the current directory. |
| **Context file scanning*- | Recursively collects documentation files from `ai/global` and `ai/projects/<project>`. |
| **Retrieval policy*- | A declarative YAML policy controls *which- artifacts are selected per intent (`planning`, `coding`, `review`, `general`). |
| **Grounded prompts*- | Builds a structured request payload from retrieved artifacts, session state, and user input, then sends it to Ollama. |
| **Persistent sessions*- | Stores resumable, multi-turn chat sessions on disk using `session.json` and `messages.jsonl`. |
| **Conversation scaling*- | Summarizes older turns into a rolling summary so long-running chats remain usable. |
| **Diagnostics*- | Lets you inspect selected files and fully constructed prompts before sending anything to Ollama. |

---

## What AiContext Solves

Local models are powerful, but without context they do not know your:

- architecture
- ADRs
- constraints
- glossary
- project-specific rules

AiContext makes local conversations more reliable by ensuring the model sees:

- your **global documents**
- your **project documents**
- the **right subset*- of those documents for the current intent
- the **relevant conversation history*- for the current session

This is especially useful for:

- architecture discussions
- ADR review
- design validation
- implementation planning
- long-running, project-scoped conversations

---

## How It Works

At a high level, each request follows this flow:

1. Resolve the current project from your location under `ai/projects/<project>`.
2. Load the retrieval policy from `ai/tooling/config/retrieval.yaml`.
3. Select the appropriate files for the chosen intent.
4. Load the selected artifacts.
5. Load the current session’s rolling summary and recent message history.
6. Build a structured message payload.
7. Send the payload to Ollama.
8. Persist the user message and assistant response back to disk.

This makes the system:

- **local-first**
- **inspectable**
- **repeatable**
- **grounded in documentation**

---

## Folder Convention

The module expects an `ai/` workspace above your working directory:

```text
<repo-root>/
└── ai/
    ├── global/                        # Cross-project context shared by all projects
    │   ├── constitution.md
    │   ├── principles.md
    │   └── glossary.md
    ├── projects/
    │   └── <project-name>/            # Per-project documentation artifacts
    │       ├── project.md
    │       ├── context.md
    │       ├── constraints.md
    │       ├── architecture/
    │       ├── decisions/
    │       ├── domain/
    │       ├── quality/
    │       └── .sessions/             # Auto-created; persisted session data
    └── tooling/
        └── config/
            └── retrieval.yaml         # Retrieval policy
````

`Resolve-AiContextPath` walks upward from your current directory until it finds a folder whose parent is `projects/`, then derives both the project root and the `ai/global` sibling automatically.

That means you can run the module from:

```text
ai/projects/llamarc42
```

or from a nested folder such as:

```text
ai/projects/llamarc42/architecture
```

and it will still resolve the correct project and global paths.

---

## Requirements

| Requirement                                                     | Version                                             |
| --------------------------------------------------------------- | --------------------------------------------------- |
| PowerShell                                                      | 7.0+                                                |
| [Ollama](https://ollama.com)                                    | Running locally (default: `http://localhost:11434`) |
| [powershell-yaml](https://github.com/cloudbase/powershell-yaml) | Required for retrieval policy loading               |

Install the YAML module if you plan to use retrieval policies:

```powershell
Install-Module -Name powershell-yaml -Scope CurrentUser
```

> Note: long-running session summarization also uses the configured Ollama model through the local `/api/chat` endpoint.

---

## Installation

Clone or copy the `AiContext/` folder to a location on your `$env:PSModulePath`, then import it:

```powershell
Import-Module ./AiContext/AiContext.psd1
```

Or import directly by path:

```powershell
Import-Module /path/to/powershell/AiContext/AiContext.psd1
```

---

## Quick Start

### Start an interactive architecture-aware chat

```powershell
Set-Location ai/projects/llamarc42

Start-OllamaProjectChat -Name 'architecture-review' -Intent planning
```

This will:

- resolve the current project
- load the retrieval policy
- select planning-relevant artifacts
- create or resume a session
- start a persistent multi-turn conversation loop

Type `exit`, `quit`, or `:q` to end the session.

---

### Resume a prior session and continue it

```powershell
$session = Resume-OllamaProjectSession -Name 'architecture'

Send-OllamaProjectSessionMessage `
    -Session $session `
    -Prompt 'What open questions remain from this discussion?' `
    -Intent planning
```

This is useful for continuing a project conversation over hours or days.

---

### Inspect retrieved context before sending anything

```powershell
Get-OllamaProjectContextDebug -Intent planning |
    Select-Object -ExpandProperty Files |
    Format-Table Scope, RelativePath, Reason, Priority, OrderRank
```

This shows:

- which files will be included
- why each file was selected
- how they were ranked

---

### Inspect the exact prompt without calling Ollama

```powershell
$session = New-OllamaProjectSession -Name 'prompt-inspection'

Send-OllamaProjectSessionMessage `
    -Session $session `
    -Prompt 'What risks are documented for this project?' `
    -Intent review `
    -InspectPrompt
```

This returns the fully constructed request payload without:

- writing the user message to the transcript
- calling the Ollama endpoint

It is useful for debugging and demos.

---

## Retrieval Policy

AiContext uses a YAML retrieval policy at:

```text
ai/tooling/config/retrieval.yaml
```

Required top-level sections:

- `version`
- `global`
- `project`
- `retrieval`

Example:

```yaml
version: 1

global:
  always_include:
    - constitution.md
    - principles.md
    - glossary.md

project:
  include:
    - project.md
    - context.md
    - constraints.md
  folders:
    architecture:
      priority: high
    decisions:
      priority: high
    domain:
      priority: medium
    quality:
      priority: medium

retrieval:
  strategies:
    planning:
      include:
        - architecture/**
        - decisions/**
        - constraints.md
      max_files: 10

    coding:
      include:
        - domain/**
        - constraints.md
      max_files: 8

    review:
      include:
        - decisions/**
        - architecture/**
        - quality/**
      max_files: 12

    general:
      include:
        - project.md
        - context.md
      max_files: 6

history:
  max_messages: 50
  summarize_after: 30
```

### Selection order

For each request, AiContext selects files in this order:

1. `global.always_include`
2. `project.include`
3. intent-specific strategy matches from `retrieval.strategies.<intent>.include`

Intent-specific matches are then:

- ranked by configured folder priority (`high` → `medium` → `low`)
- deduplicated
- capped by `max_files`

> Current retrieval is policy-driven and file-based. AiContext does **not*- yet use embeddings or semantic vector search; instead it selects artifacts using explicit YAML rules, folder priorities, and per-intent file limits.

---

## Working Examples

### Example 1: Architecture planning

Start an architecture-focused session:

```powershell
Set-Location ai/projects/llamarc42

Start-OllamaProjectChat -Name 'csharp-core' -Intent planning
```

Then ask:

```text
What constraints and ADRs should govern the move from PowerShell to a C# core?
```

Why this is a good demo:

- it exercises planning retrieval
- it should pull in architecture, decisions, and constraints
- it reflects a real project question

---

### Example 2: Design review / drift check

Start a review-oriented session:

```powershell
Start-OllamaProjectChat -Name 'api-boundary-review' -Intent review
```

Then ask:

```text
Given the current architecture and ADRs, what risks do you see in introducing an API before the C# core is stable?
```

Why this is a good demo:

- it shows architecture-aware reasoning
- it demonstrates policy-driven review context
- it surfaces tradeoffs instead of generic advice

---

### Example 3: Session continuity over time

List recent sessions:

```powershell
Get-OllamaProjectSessionList -First 10
```

Resume one:

```powershell
$session = Resume-OllamaProjectSession -Name 'csharp-core'
```

Continue the discussion:

```powershell
Send-OllamaProjectSessionMessage `
    -Session $session `
    -Prompt 'Summarize the decisions we have already made and the main open questions.' `
    -Intent planning
```

View the most recent transcript entries:

```powershell
Get-OllamaProjectSessionMessage -Session $session -Tail 10
```

Why this is a good demo:

- it proves sessions are durable
- it makes persistence tangible
- it shows continuity across days

---

### Example 4: Programmatic use in scripts

Use AiContext from a script without launching the interactive loop:

```powershell
$session = New-OllamaProjectSession -Name 'scripted-review'

$result = Send-OllamaProjectSessionMessage `
    -Session $session `
    -Prompt 'What project risks are currently documented?' `
    -Intent review `
    -RawResponse

$result.Response
```

Why this is useful:

- shows automation-friendly usage
- makes it clear the module is not just a REPL
- useful for pipelines, reports, and tooling

---

## Session Storage

Each session lives under:

```text
ai/projects/<project>/.sessions/<timestamp-name>/
```

Example:

```text
ai/projects/llamarc42/.sessions/2026-04-01_101500-architecture-review/
```

Each session contains:

- `session.json` — metadata such as model, timestamps, tracked files, and rolling summary
- `messages.jsonl` — append-only transcript, one JSON object per line

This makes sessions:

- easy to inspect
- easy to debug
- easy to parse from external tools

---

## Module Reference

### Path & File Resolution

| Function                | Description                                                                                                                                                          |
| ----------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `Resolve-AiContextPath` | Walks upward from `-ProjectFolder` to locate the `ai/projects/<project>` root and resolve the matching `ai/global` folder.                                           |
| `Get-AiContextFiles`    | Recursively scans a path and returns `FileInfo` objects for all files matching the requested extensions.                                                             |
| `Get-AiContextContent`  | Reads a set of files and concatenates them into a single string, optionally wrapping each with `BEGIN/END FILE` markers.                                             |
| `Get-AiProjectContext`  | Combines global and project file scans and content into one object with a `CombinedContent` string. Mainly useful for full-context inspection and earlier workflows. |

### Retrieval Policy & Context

| Function                   | Description                                                                                                                                               |
| -------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `Get-RetrievalPolicy`      | Loads and validates `retrieval.yaml`. Requires the `powershell-yaml` module. Returns a `Llamarc42.RetrievalPolicy` object.                                |
| `Resolve-RetrievalContext` | Applies a retrieval policy for a given intent, ranks and deduplicates artifacts, and returns a `Llamarc42.RetrievalContext` with an ordered `Items` list. |

### Session Management

| Function                          | Description                                                                                                                                  |
| --------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------- |
| `New-OllamaProjectSession`        | Creates a session folder under `.sessions/`, writes `session.json` and an empty `messages.jsonl`. Returns an `Ollama.ProjectSession` object. |
| `Get-OllamaProjectSession`        | Loads a session by id, folder path, or most-recent default.                                                                                  |
| `Get-OllamaProjectSessionList`    | Returns summary info (`Ollama.ProjectSessionInfo`) for all sessions in the project, with optional name filter and result cap.                |
| `Select-OllamaProjectSession`     | Interactive prompt that lets the user pick a session from a numbered list.                                                                   |
| `Resume-OllamaProjectSession`     | Returns the most-recent session or resolves a specific one by partial name/title/id match.                                                   |
| `Add-OllamaProjectSessionMessage` | Appends a `user`, `assistant`, or `system` message to `messages.jsonl` and updates session metadata.                                         |
| `Get-OllamaProjectSessionMessage` | Reads messages from `messages.jsonl`, with optional `-Tail` and `-Raw` flags.                                                                |

### Conversation Scaling & Summarization

| Function                                     | Description                                                                                                                                                                                                                       |
| -------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `Get-OllamaProjectSessionConversationWindow` | Builds the active conversation window for a session: returns recent messages to include in the next request, identifies older messages that should be folded into the rolling summary, and surfaces the current `RollingSummary`. |
| `Update-OllamaProjectSessionSummary`         | Produces and persists a condensed rolling summary when older messages exceed the configured threshold.                                                                                                                            |

### Chat & Interaction

| Function                           | Description                                                                                                                                                                                                                                                        |
| ---------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| `Send-OllamaProjectSessionMessage` | Full retrieval + session pipeline: resolves retrieval context for the intent, updates the rolling summary when needed, builds the request payload, calls `/api/chat`, and persists both the user prompt and assistant reply. Accepts either `-Session` or `-Path`. |
| `Start-OllamaProjectChat`          | Entry-point REPL: resolves paths, lets the user resume or create a session, then loops on `Read-Host` until `exit`/`quit`/`:q`.                                                                                                                                    |

### Diagnostics

| Function                                          | Description                                                                                                                                                                                          |
| ------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `Get-OllamaProjectContextDebug`                   | Resolves project/global paths, loads the retrieval policy, builds the retrieval context for the requested intent, and returns a debug object showing selected artifact files and history thresholds. |
| `Send-OllamaProjectSessionMessage -InspectPrompt` | Returns the fully constructed request payload without writing to the transcript or calling Ollama. Useful for debugging and demos.                                                                   |

---

## Repository Layout

```text
powershell/
├── AiContext/
│   ├── AiContext.psd1
│   ├── AiContext.psm1
│   ├── private/
│   │   ├── ConvertTo-Slug.ps1
│   │   ├── Find-ArtifactMatches.ps1
│   │   ├── Get-ArtifactRelativePath.ps1
│   │   ├── Get-RetrievalContextContent.ps1
│   │   ├── Get-SessionTimestamp.ps1
│   │   ├── Invoke-OllamaProjectChat.ps1
│   │   ├── New-InteractiveOllamaProjectSession.ps1
│   │   ├── New-SessionObject.ps1
│   │   ├── Resolve-OllamaProjectSessionByName.ps1
│   │   ├── Resolve-SessionObject.ps1
│   │   └── Save-SessionMetadata.ps1
│   └── public/
│       ├── Add-OllamaProjectSessionMessage.ps1
│       ├── Get-AiContextContent.ps1
│       ├── Get-AiContextFiles.ps1
│       ├── Get-AiProjectContext.ps1
│       ├── Get-OllamaProjectContextDebug.ps1
│       ├── Get-OllamaProjectSession.ps1
│       ├── Get-OllamaProjectSessionConversationWindow.ps1
│       ├── Get-OllamaProjectSessionList.ps1
│       ├── Get-OllamaProjectSessionMessage.ps1
│       ├── Get-RetrievalPolicy.ps1
│       ├── New-OllamaProjectSession.ps1
│       ├── Resolve-AiContextPath.ps1
│       ├── Resolve-RetrievalContext.ps1
│       ├── Resume-OllamaProjectSession.ps1
│       ├── Select-OllamaProjectSession.ps1
│       ├── Send-OllamaProjectSessionMessage.ps1
│       ├── Start-OllamaProjectChat.ps1
│       └── Update-OllamaProjectSessionSummary.ps1
├── .gitignore
└── LICENSE
```

---

## Design Notes

- **Strict mode**: `Set-StrictMode -Version Latest` and `$ErrorActionPreference = 'Stop'` are set at module load time to surface errors early.
- **Typed objects**: returned objects carry `PSTypeName` values such as `Ollama.ProjectSession` and `Llamarc42.RetrievalContext`.
- **JSONL transcripts**: session messages are stored one JSON object per line in `messages.jsonl`, making them easy to tail, grep, and parse.
- **No cloud dependency**: all LLM calls go to a local Ollama instance.
- **Deterministic artifact ordering**: retrieved artifacts are sorted by rank and relative path, ensuring reproducible prompts.
- **Policy-driven retrieval**: current retrieval is file- and rule-based, not embeddings-based semantic search.

---

## Troubleshooting

### `ConvertFrom-Yaml` is not available

Install the YAML module:

```powershell
Install-Module -Name powershell-yaml -Scope CurrentUser
```

---

### Ollama connection failed

Ensure Ollama is running locally and reachable:

```powershell
ollama list
```

Default endpoint:

```text
http://localhost:11434
```

---

### Project path could not be resolved

Run the module from somewhere inside:

```text
ai/projects/<project>
```

or pass `-ProjectFolder` explicitly where supported.

---

### Retrieval policy not found

Ensure this file exists:

```text
ai/tooling/config/retrieval.yaml
```

---

### No assistant message content was returned

Use prompt inspection to verify the constructed request:

```powershell
Send-OllamaProjectSessionMessage `
    -Session $session `
    -Prompt 'Test prompt' `
    -InspectPrompt
```

Then verify:

- selected files
- request structure
- Ollama model availability

---

## License

See [LICENSE](./LICENSE).
