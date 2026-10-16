# Claude Code provider and the "brain"

This fork makes Coucou the front door to a knowledge vault (an Obsidian "brain") and
lets every Claude feature run on the user's own Claude login instead of an Anthropic
API key. GitHub build only (`#if !APPSTORE`): the App Store build is sandboxed and
cannot start a subprocess.

## How it signs in

Coucou never sees a key or a token. It starts the user's own, unmodified `claude` CLI
(`claude -p`, stream-json in and out), which is signed in with the account the user
chose in Claude Code (claude.ai subscription, Team/Enterprise seat or Console). This is
the route Anthropic's terms leave open: third-party apps may not offer Claude.ai login,
nor collect, store or relay Claude.ai credentials or session tokens, but an end user may
run the unmodified Claude Code binary with their own subscription
(<https://code.claude.com/docs/en/legal-and-compliance>, "Authentication and credential
use"). Do not replace this with an OAuth flow or by reading Claude Code's keychain item.

## What runs where

| Feature | Process | Folder | Model | Tools |
|---|---|---|---|---|
| Chat (provider "Claude Code") | one per conversation, `--resume` across restarts | the brain folder (Settings → Chat) | Settings (opus / sonnet / haiku) | Claude Code's own; read-only ones pre-approved |
| Flow clean-up | warm, renewed every 5 requests | app folder | haiku | none |
| Notetaker summary | one-off | app folder | sonnet | none |

`ClaudeCodeSession` (App/ClaudeCode) owns the process: one turn at a time, timeout →
kill → the next turn resumes the conversation, idle → stdin closed so Claude Code ends
the session normally (SessionEnd hooks run). `ClaudeAccess` decides who answers: Claude
Code when it is installed and either no key is saved or the chat uses it.

### The brain chat

- Runs in the brain folder with the user's and the project's settings (its CLAUDE.md,
  skills, commands, agents, plugins and hooks apply) but not the folder's
  `settings.local.json`: allow rules granted over time in the terminal (`python3 *`,
  `curl *`…) stay out (`--setting-sources user,project`). Plugin MCP servers are skipped
  too (`--strict-mcp-config`): they cost seconds at every start.
- Free: Read, Grep, Glob, WebSearch, TodoWrite. Always asked, whatever allow rule the
  user's settings carry: Bash, Write, Edit, MultiEdit, NotebookEdit, WebFetch (`--settings`
  with `permissions.ask`, which beats `allow`; `--permission-mode default`). A note, a
  dropped file or a page can carry a prompt injection, and commands, writes and fetched
  URLs are how data leaves. A search command that runs a script therefore asks once.
- `COUCOU_BRAIN=1` is set. nb-hook tags its events `coucou_brain`; HookServer keeps them
  off the pills (the chat shows the progress) and turns its PermissionRequests into an
  Allow / Deny card labelled "Mochi · <folder>" over the chat, showing the command, URL
  or file. No "Always" (it would write a lasting allow rule into the brain's settings).
  No answer = the tool is denied (print mode).
- AskUserQuestion is removed (nobody could answer it in print mode).
- A vault can recognise these runs through `COUCOU_BRAIN=1` (e.g. skip start-of-session
  automations in its SessionStart hook).
- Print mode skips the folder-trust prompt: the brain folder's project hooks run. Only
  pick a folder you trust.

## The brain's own settings: `.coucou/brain.json`

Coucou knows nothing about how a given vault is organised. A brain can describe itself
in an optional `<brain folder>/.coucou/brain.json` (example:
[brain.example.json](brain.example.json)). It lives with the vault, so one person's
folders, commands and services never end up in Coucou. Every key is optional:

- `prompt`: instructions appended to Mochi's brain prompt (which search commands or
  agents to use, what to leave alone).
- `inbox`: where « Save to brain » writes. `folder` and `attachments` (both inside the
  vault), `ignore` (file names that are not notes) and `noteHeader` (lines under the
  note's title, with `{date}`, `{source}` and `{title}`).
- `counters`: up to 3 rows on the Brain card. Each has a `label`, a `kind`
  (`notesWithoutFrontmatter` or `files`), `paths` (relative to the vault, `~/…` or
  absolute), a `pattern` (default `*.md`) and an optional `action` that either `send`s a
  message to the brain chat or opens it with a `draft` typed in.
- `services`: up to 2 local services, each with a status dot from `health` (loopback
  addresses only) and a button for `open` (http/https).

Without the file, the card offers Ask and Obsidian, and « Save to brain » writes to
`Inbox/` (attachments in `Inbox/attachments/`). The file is read again at every refresh.

## Measured (Apple Silicon Mac)

- Chat, warm process: about 1 s per short turn; first turn of a conversation 2.5–3.5 s.
- Brain questions that read notes: 8–12 s.

## Checks

```sh
bash scripts/test-claude-code.sh   # parser, arguments, process session (fake CLI)
bash scripts/test-brain-config.sh  # .coucou/brain.json parsing
bash scripts/test-brain-status.sh  # Brain card counters
bash scripts/test-brain-inbox.sh   # « Save to brain »
```
