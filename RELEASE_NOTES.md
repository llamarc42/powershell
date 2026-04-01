# Release Notes — llamarc42 v1.0.0

**Release date:** 2026-04-01  
**Module:** `llamarc42`  
**Author:** Jeffrey Patton (Patton-Tech)  
**License:** GNU General Public License v3.0  
**PowerShell requirement:** 7.0+  
**Compatible editions:** Core, Desktop

---

## Overview

`llamarc42` is a PowerShell module that provides **architecture-aware, file-based retrieval over local project documentation**, backed by a locally running [Ollama](https://ollama.com) instance.

The module walks your `ai/projects/<project>` workspace, applies a declarative YAML retrieval policy, and sends **grounded** prompts to Ollama for either persistent, resumable chat sessions or programmatic session-based queries.

> `llamarc42` does **not** fine-tune or train the model. It retrieves documentation artifacts at runtime and injects only the policy-selected context into each request.

---

## What's New in v1.0.0

This is the **initial stable release**. All features described below were introduced between the first commit on 2026-03-30 and the v1.0.0 tag on 2026-04-01.

---

## Features

### Path & File Resolution

| Function | Description |
|---|---|
| `Resolve-Llamarc42Path` | Walks upward from a project folder to locate the `ai/projects/<project>` root and resolves the matching `ai/global` folder. Returns a structured paths object used throughout the module. |
| `Get-Llamarc42Files` | Recursively scans a folder tree and returns files whose extensions match a configurable set (default: `.md`, `.txt`). |
| `Get-Llamarc42Content` | Reads a list of files, optionally wraps each in begin/end headers, and returns a single combined text payload suitable for use as AI context. |
| `Get-Llamarc42ProjectContext` | Resolves project and global folders, gathers matching files from each, and returns a combined context object containing both file lists and the merged text payload. |

### Retrieval Policy & Context (Fixes #7, #9)

The retrieval system replaces the earlier brute-force approach of loading all context files. A declarative YAML policy (`tooling/config/retrieval.yaml`) controls exactly which artifacts are selected per conversational intent (`planning`, `coding`, `review`, `general`).

| Function | Description |
|---|---|
| `Get-Llamarc42RetrievalPolicy` | Loads and validates the retrieval policy YAML file. Resolves the default policy path from the AI workspace root when no explicit path is supplied. Returns a `Llamarc42.RetrievalPolicy` object. |
| `Resolve-Llamarc42RetrievalContext` | Applies the retrieval policy for a given intent against the project and global artifact sets. Returns an ordered `Llamarc42.RetrievalContext` object that lists only the selected files. |

### Session Management

Persistent, resumable multi-turn sessions are stored on disk as `session.json` metadata and a `messages.jsonl` transcript under each project's `.sessions` folder.

| Function | Description |
|---|---|
| `New-Llamarc42ProjectSession` | Creates a new session folder under `.sessions`, initializes metadata and message files, and returns the session object. Accepts a name, optional title, default model, tags, and artifact extension tracking list. |
| `Get-Llamarc42ProjectSession` | Loads an existing session from a session id, a folder path, or the most recent session for a project. Returns a `Llamarc42.ProjectSession` object. |
| `Get-Llamarc42ProjectSessionList` | Reads all session metadata from the project's `.sessions` folder, sorts newest-first, and returns `Llamarc42.ProjectSessionInfo` summaries with optional name filtering and result limiting. |
| `Get-Llamarc42ProjectSessionMessage` | Reads the session `messages.jsonl` transcript. Supports a `–Tail` parameter to retrieve only the most recent N messages and a `–Raw` switch for unprocessed JSON records. |
| `Add-Llamarc42ProjectSessionMessage` | Appends a user, assistant, or system message to the session transcript, updates the session metadata, and returns the written message. Accepts pipeline input. |
| `Resume-Llamarc42ProjectSession` | Returns the most recent session for a project, or resolves a specific session by partial name, title, or id. |
| `Select-Llamarc42ProjectSession` | Interactively displays existing sessions, prompts for a numeric choice, and returns the selected session. Supports `–AllowNew` to offer a "start new session" option. |

### Conversation Scaling & Summarization (Fixes #10)

Long-running sessions are kept usable through a rolling summary mechanism that folds older turns into a condensed summary, leaving only the most recent messages in the active context window.

| Function | Description |
|---|---|
| `Get-Llamarc42ProjectSessionConversationWindow` | Loads the session transcript, computes the active conversation window (most recent messages), and identifies older messages that should be folded into the rolling summary. Configurable via `–MaxMessages` and `–SummarizeAfter`. |
| `Update-Llamarc42ProjectSessionSummary` | Builds the conversation window for a session, calls the Ollama chat endpoint to summarize older messages when the threshold is reached, stores the result in the session's rolling summary, and persists updated metadata. |

### Chat & Interaction

| Function | Description |
|---|---|
| `Send-Llamarc42ProjectSessionMessage` | The core send function. Loads the retrieval policy, resolves the intent-specific retrieval context, updates the rolling summary when needed, builds a structured prompt from retrieved artifacts, rolling summary, and recent history, calls the Ollama `/api/chat` endpoint, stores both the user and assistant messages, and returns the chat result. |
| `Start-Llamarc42ProjectChat` | Enters an interactive read-prompt-respond loop. Resolves project paths, allows resuming or creating a session, and drives `Send-Llamarc42ProjectSessionMessage` for each input line. Supports `–RefreshArtifactFiles` to update tracked file metadata after each send. |

### Diagnostics (Fixes #6)

| Function | Description |
|---|---|
| `Get-Llamarc42ProjectContextDebug` | Returns a diagnostic object showing the retrieval policy, selected files, intent strategy, and conversation window settings **without** calling Ollama. Use this to audit exactly what context and history will be injected into the next prompt. |

---

## Private Helpers

The following internal functions support the public API and are not exported:

| Helper | Role |
|---|---|
| `ConvertTo-Slug` | Normalizes a string for session folder and id naming (lowercase, hyphens, collapse repeats). |
| `Find-ArtifactMatches` | Matches candidate artifact files against a wildcard pattern using artifact-relative paths. |
| `Get-ArtifactRelativePath` | Computes a forward-slash-separated path relative to a root folder. |
| `Get-RetrievalContextContent` | Reads selected artifacts from a retrieval context, optionally wraps each in scope-aware headers, and returns the combined content string for prompt construction. |
| `Get-SessionTimestamp` | Returns the current local time formatted as `yyyy-MM-dd_HHmmss` for session id generation. |
| `New-InteractiveLlamarc42ProjectSession` | Prompts the user for a session name and creates the session during interactive chat startup. |
| `New-SessionObject` | Maps persisted session metadata into the canonical `Llamarc42.ProjectSession` shape. |
| `Resolve-Llamarc42ProjectSessionByName` | Searches a session list for partial name/title/id matches; errors on ambiguous matches. |
| `Resolve-SessionObject` | Normalizes a session object, folder path, or default session into a full session object. |
| `Save-SessionMetadata` | Serializes the current session state and writes it to the session's `session.json` file. |

---

## Test Coverage

A comprehensive Pester test suite was added for all 18 public functions, organized under `llamarc42/tests/`. Tests were written in multiple passes:

- Initial coverage for all 15 public functions present at that time (PR #12)
- Additional coverage for `Get-Llamarc42ProjectSessionConversationWindow`, `Update-Llamarc42ProjectSessionSummary`, and expanded `Send-Llamarc42ProjectSessionMessage` scenarios (PR #13)
- Tests for `Get-Llamarc42ProjectContextDebug` and further `Send-Llamarc42ProjectSessionMessage` edge cases (PR #16)

---

## Breaking Changes

None. This is the initial stable release.

---

## Known Issues / Limitations

- `Get-Llamarc42RetrievalPolicy` requires the [`powershell-yaml`](https://www.powershellgallery.com/packages/powershell-yaml) module (`ConvertFrom-Yaml`) to parse `retrieval.yaml`. If it is not installed, policy loading will fail with a `ConvertFrom-Yaml is not available` error.
- The module requires a locally running Ollama instance. Connection failures will produce an `Ollama connection failed` error.
- The AI workspace must follow the `ai/projects/<project>` folder convention. If the structure cannot be resolved, functions will throw a `Project path could not be resolved` error.

---

## Repository Timeline

| Date | Event |
|---|---|
| 2026-03-30 | Initial commit — repository scaffolded with `.gitignore`, `LICENSE`, and placeholder `README.md` |
| 2026-03-30 | `AiContext.psd1` module manifest created with initial description and metadata |
| 2026-03-30 | `AiContext.psm1` added — monolithic module containing all project management functions |
| 2026-03-31 | Module restructured into the standard `public/` / `private/` folder layout |
| 2026-03-31 | Retrieval policy and context resolution functions added (Fixes #7) |
| 2026-03-31 | `Send-OllamaProjectSessionMessage` refactored to integrate retrieval policy; `Get-RetrievalContextContent` helper added (Fixes #9) |
| 2026-03-31 | Comprehensive README written (PR #11) |
| 2026-03-31 | Pester test suite added for all 15 public functions (PR #12) |
| 2026-03-31 | `Get-OllamaProjectSessionConversationWindow` and `Update-OllamaProjectSessionSummary` added (Fixes #10) |
| 2026-03-31 | Tests added for conversation window and summarization functions (PR #13) |
| 2026-04-01 | Unused private function `Invoke-OllamaProjectChat` removed (PR #14) |
| 2026-04-01 | Module version bumped to `1.0.0`; `Get-OllamaProjectContextDebug` added (Fixes #6) |
| 2026-04-01 | README updated for new functions and `Send-OllamaProjectSessionMessage` changes (PR #15) |
| 2026-04-01 | Tests for `Get-OllamaProjectContextDebug` added (PR #16) |
| 2026-04-01 | Module renamed from `AiContext`/`OllamaProject` to `llamarc42` (PR #17) |

---

## Upgrade / Migration Notes

This is the first release. No migration is required.

For users who were running pre-release code from the `AiContext` or `OllamaProject` naming era:

- The module folder is now `llamarc42/`
- The manifest is now `llamarc42.psd1`
- All exported function names now use the `Llamarc42` noun prefix (e.g., `Get-OllamaProjectSession` → `Get-Llamarc42ProjectSession`)
- All custom type names now use the `Llamarc42.` prefix (e.g., `Llamarc42.ProjectSession`)

---

## Acknowledgements

Module developed by **Jeffrey Patton** (Patton-Tech) with AI-assisted development via GitHub Copilot (jeffpatton1971).
