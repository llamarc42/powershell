# AiContext PowerShell Module

A PowerShell module that implements a **file-based Retrieval-Augmented Generation (RAG)** workflow on top of a locally-running [Ollama](https://ollama.com) instance. It walks your `ai/projects/<project>` directory structure, selects the right documentation artifacts for the task at hand, and delivers grounded prompts to an Ollama model—either as one-off queries or as persistent, resumable chat sessions.

---

## Table of Contents

- [AiContext PowerShell Module](#aicontext-powershell-module)
  - [Table of Contents](#table-of-contents)
  - [Overview](#overview)
  - [Folder Convention](#folder-convention)
  - [Requirements](#requirements)
  - [Installation](#installation)
  - [Quick Start](#quick-start)
    - [One-off query (no session)](#one-off-query-no-session)
    - [Interactive multi-turn chat](#interactive-multi-turn-chat)
    - [Session management](#session-management)
  - [Retrieval Policy](#retrieval-policy)
  - [Module Reference](#module-reference)
    - [Path \& File Resolution](#path--file-resolution)
    - [Retrieval Policy \& Context](#retrieval-policy--context)
    - [One-off Ollama Queries](#one-off-ollama-queries)
    - [Session Management](#session-management-1)
    - [Interactive Chat](#interactive-chat)
    - [Diagnostics](#diagnostics)
  - [Repository Layout](#repository-layout)
  - [Design Notes](#design-notes)
  - [License](#license)

---

## Overview

`AiContext` solves a common problem when working with local AI models: how do you reliably feed the model the *right* subset of your project documentation without copying and pasting files by hand?

The module provides:

| Capability | Description |
| --- | --- |
| **Path resolution** | Automatically discovers the `ai/` workspace root by walking upward from the current directory. |
| **Context file scanning** | Recursively collects `.md`, `.txt`, and other configured extensions from `ai/global` and `ai/projects/<project>`. |
| **Retrieval policy** | A declarative YAML policy that controls *which* artifacts are included per conversational intent (`planning`, `coding`, `review`, `general`). |
| **Grounded prompts** | Builds a structured prompt payload (system instructions + retrieved context + user message) and sends it to Ollama. |
| **Persistent sessions** | Creates, stores, and resumes multi-turn chat sessions whose transcripts are persisted as JSONL files on disk. |

---

## Folder Convention

The module expects an `ai/` workspace at the root of your repository (or anywhere above your working directory):

```text
<repo-root>/
└── ai/
    ├── global/                 # Cross-project context shared by all projects
    │   ├── conventions.md
    │   └── standards.md
    ├── projects/
    │   └── <project-name>/     # Per-project documentation artifacts
    │       ├── adr/            # Architecture Decision Records
    │       ├── docs/           # Design docs, specifications, etc.
    │       ├── .sessions/      # Auto-created; persisted session data
    │       └── ...
    └── tooling/
        └── config/
            └── retrieval.yaml  # Retrieval policy (see below)
```

`Resolve-AiContextPath` walks upward from your current directory until it finds a folder whose parent is `projects/`, then derives both the project root and the `ai/global` sibling automatically.

---

## Requirements

| Requirement | Version |
| --- | --- |
| PowerShell | 7.0+ (Core or Desktop) |
| [Ollama](https://ollama.com) | Running locally (default: `http://localhost:11434`) |
| [powershell-yaml](https://github.com/cloudbase/powershell-yaml) | Required for `Get-RetrievalPolicy` / `Resolve-RetrievalContext` |

Install the YAML module if you plan to use retrieval policies:

```powershell
Install-Module -Name powershell-yaml -Scope CurrentUser
```

---

## Installation

Clone or copy the `AiContext/` folder to a location on your `$env:PSModulePath`, then import:

```powershell
Import-Module ./AiContext/AiContext.psd1
```

Or import directly by path from inside the repository:

```powershell
Import-Module /path/to/powershell/AiContext/AiContext.psd1
```

---

## Quick Start

### One-off query (no session)

```powershell
# Navigate to (or pass) your project folder
Set-Location ai/projects/my-project

# Send a grounded prompt; context is gathered automatically
Invoke-OllamaProjectChat -Prompt 'Summarize the current architecture constraints.' -Intent planning
```

### Interactive multi-turn chat

```powershell
# Start (or resume) a named session with an intent
Start-OllamaProjectChat -Name 'sprint-planning' -Intent planning
```

The shell enters a prompt loop. Type `exit`, `quit`, or `:q` to end the session.

### Session management

```powershell
# List sessions for the current project
Get-OllamaProjectSessionList -First 10

# Resume a session by partial name
$session = Resume-OllamaProjectSession -Name 'planning'

# Send a message programmatically
Send-OllamaProjectSessionMessage -Session $session -Prompt 'What ADRs affect this change?' -Intent review

# Read the transcript
Get-OllamaProjectSessionMessage -Session $session -Tail 20
```

---

## Retrieval Policy

A YAML file at `ai/tooling/config/retrieval.yaml` controls how artifacts are selected for each intent. Required top-level sections: `version`, `global`, `project`, and `retrieval`.

```yaml
version: 1

global:
  always_include:
    - conventions.md
    - standards.md

project:
  include:
    - README.md
  folders:
    adr:
      priority: high
    docs:
      priority: medium

retrieval:
  strategies:
    planning:
      include:
        - adr/*.md
        - docs/design*.md
      max_files: 10
    coding:
      include:
        - docs/api*.md
      max_files: 15
    review:
      include:
        - adr/*.md
        - docs/*.md
    general:
      include:
        - docs/*.md
```

**Selection order** per request:

1. `global.always_include` files (loaded first, ranked highest).
2. `project.include` baseline files.
3. Intent-specific `retrieval.strategies.<intent>.include` patterns, sorted by configured folder priority (`high` → `medium` → `low`), capped by `max_files`.

---

## Module Reference

### Path & File Resolution

| Function | Description |
| --- | --- |
| `Resolve-AiContextPath` | Walks upward from `-ProjectFolder` to locate the `ai/projects/<project>` root and resolve the matching `ai/global` folder. |
| `Get-AiContextFiles` | Recursively scans a path and returns `FileInfo` objects for all files matching the requested extensions. |
| `Get-AiContextContent` | Reads a set of files and concatenates them into a single string, optionally wrapping each with `BEGIN/END FILE` markers. |
| `Get-AiProjectContext` | Combines global and project file scans and content into one object with a `CombinedContent` string. |

### Retrieval Policy & Context

| Function | Description |
| --- | --- |
| `Get-RetrievalPolicy` | Loads and validates `retrieval.yaml`. Requires the `powershell-yaml` module. Returns a `Llamarc42.RetrievalPolicy` object. |
| `Resolve-RetrievalContext` | Applies a retrieval policy for a given intent, ranks and deduplicates artifacts, and returns a `Llamarc42.RetrievalContext` with an ordered `Items` list. |

### One-off Ollama Queries

| Function | Description |
| --- | --- |
| `Invoke-OllamaProjectChat` *(private)* | Builds a full prompt from project context and sends it to the Ollama `/api/generate` endpoint. Used internally; call via `Start-OllamaProjectChat` or directly for scripted use. |

### Session Management

| Function | Description |
| --- | --- |
| `New-OllamaProjectSession` | Creates a session folder under `.sessions/`, writes `session.json` and an empty `messages.jsonl`. Returns an `Ollama.ProjectSession` object. |
| `Get-OllamaProjectSession` | Loads a session by id, folder path, or most-recent default. |
| `Get-OllamaProjectSessionList` | Returns summary info (`Ollama.ProjectSessionInfo`) for all sessions in the project, with optional name filter and result cap. |
| `Select-OllamaProjectSession` | Interactive prompt that lets the user pick a session from a numbered list. |
| `Resume-OllamaProjectSession` | Returns the most-recent session or resolves a specific one by partial name/title/id match. |
| `Add-OllamaProjectSessionMessage` | Appends a `user`, `assistant`, or `system` message to `messages.jsonl` and updates session metadata. |
| `Get-OllamaProjectSessionMessage` | Reads messages from `messages.jsonl`, with optional `-Tail` and `-Raw` flags. |
| `Get-OllamaProjectSessionConversationWindow` | Builds the active conversation window for a session: returns the most recent messages to include in the next request, identifies older messages that should be folded into the rolling summary, and surfaces the current `RollingSummary`. Returns a `Llamarc42.ConversationWindow` object. |
| `Update-OllamaProjectSessionSummary` | Inspects the session transcript and, when older messages exceed the configured `SummarizeAfter` threshold, sends them to the Ollama `/api/chat` endpoint to produce a condensed rolling summary. Persists the updated summary to `session.json` and returns the updated session. |
| `Send-OllamaProjectSessionMessage` | Full RAG + chat pipeline: resolves retrieval context for the intent, updates the rolling conversation summary via `Update-OllamaProjectSessionSummary` when needed, builds the message array (system + rolling summary + history + user) via `Get-OllamaProjectSessionConversationWindow`, calls `/api/chat`, and persists both the user prompt and assistant reply. Accepts a session object (`-Session`) or a path to a session folder (`-Path`). Use `-InspectPrompt` to return the fully constructed request payload without writing messages or calling the endpoint. Use `-RawResponse` to include the raw Ollama response and full message array alongside the normalized result. Use `-RefreshArtifactFiles` to update the session's tracked artifact file list from the resolved retrieval context. |

### Interactive Chat

| Function | Description |
| --- | --- |
| `Start-OllamaProjectChat` | Entry-point REPL: resolves paths, lets the user resume or create a session, then loops on `Read-Host` until `exit`/`quit`/`:q`. |

### Diagnostics

| Function | Description |
| --- | --- |
| `Get-OllamaProjectContextDebug` | Resolves the project and global paths, loads the retrieval policy, builds the retrieval context for the requested intent, and returns a `Llamarc42.ContextDebug` object that shows the selected artifact files and the `history.max_messages` / `history.summarize_after` thresholds defined by the policy. Useful for verifying which files will be included in a prompt before actually sending one. |

---

## Repository Layout

```text
powershell/
├── AiContext/
│   ├── AiContext.psd1          # Module manifest (version, exports, metadata)
│   ├── AiContext.psm1          # Module loader: dot-sources Private then Public
│   ├── private/                # Internal helpers (not exported)
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
│   └── public/                 # Exported functions
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
- **PSCustomObject typing**: Returned objects carry `PSTypeName` properties (`Ollama.ProjectSession`, `Llamarc42.RetrievalContext`, etc.) to support `Format.ps1xml` customization if desired.
- **JSONL transcripts**: Session messages are stored one JSON object per line in `messages.jsonl`, making them easy to tail, grep, and parse externally.
- **No cloud dependency**: All LLM calls go to a local Ollama instance. The default model is `gpt-oss:20b`, but every function accepts a `-Model` override.
- **Deterministic artifact ordering**: Retrieved artifacts are sorted by `OrderRank` (global first, then project base, then intent-specific) and then by relative path, ensuring reproducible prompts.

---

## License

See [LICENSE](./LICENSE).
