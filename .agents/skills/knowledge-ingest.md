---
shortDescription: Ingest external sources (videos, articles, PDFs, meeting transcripts) into structured vault notes with extracted claims, frameworks, and action items.
usedBy: [maestro, contextualizer]
version: 1.1.0
lastUpdated: 2026-03-23
copyright: Rodrigo Canuto © 2026.
evals:
  - prompt: "here's the link to a youtube video about DDD architecture, add it to the vault"
    should_trigger: true
  - prompt: "we had a meeting about the Q2 roadmap, the transcript is in /tmp/meeting.txt — ingest it"
    should_trigger: true
  - prompt: "what notes do we have in the vault about DDD?"
    should_trigger: false
  - prompt: "summarize this PDF for me"
    should_trigger: false
---

## When to Use

**Triggers:**
- User shares a URL (YouTube, article, blog post) and wants it captured in the vault
- User provides a local file (PDF, MP4, audio, transcript) for knowledge extraction
- User says: `"ingest this"`, `"add to vault"`, `"extract from this video"`, `"process this transcript"`, `"clip this"`
- After a meeting: user provides a call transcript (from Fathom, Otter, Fireflies, etc.) for structured extraction

**Not for:**
- Quick web lookups (use direct answers or `defuddle` for one-off reads)
- Codebase-related research (use the `research` skill instead)
- API documentation fetching (use `api-docs-fetch` instead)

---

## Purpose

Transform unstructured external knowledge (videos, articles, PDFs, meeting recordings, raw transcripts) into structured, searchable vault notes with extracted insights. Closes the gap between "I consumed something useful" and "my AI can find and use it."

The pipeline runs locally where possible — no data leaves the machine for transcription.

---

## Concepts

### Source Types

| Type | Input | Extraction Method |
|------|-------|-------------------|
| **YouTube video** | URL | `yt-dlp` for transcript/subtitles, fallback to `whisper` on downloaded audio |
| **Web article** | URL | `defuddle parse <url> --md` (reuses existing skill) |
| **PDF** | Local path | Direct text extraction (`pdftotext` or Python `PyPDF2`) |
| **Video/Audio file** | Local path | `whisper` for local transcription |
| **Meeting transcript** | Local path or pasted text | Direct processing (already text) |
| **Raw text** | Pasted or file path | Direct processing |

### Output Types

Two distinct output formats based on source type:

**External Content** (video, article, PDF):
- Claims: distinct assertions worth preserving
- Frameworks: named mental models or methodologies
- Action Items: concrete techniques or steps
- Examples: real-world cases with context
- Key Quotes: verbatim notable passages

**Meeting Transcript**:
- Summary: what was discussed (2-3 paragraphs max)
- Decisions Made: each decision with rationale
- Action Items: owner + deadline + description
- Key Context: important background that influenced decisions
- Open Questions: unresolved topics for follow-up

---

## Procedure

### Step 1: Identify Source Type

Determine the source type from the user's input:
- URL starting with `youtube.com` or `youtu.be` → YouTube video
- URL to a web page → Web article
- Local `.pdf` file → PDF
- Local `.mp4`, `.webm`, `.m4a`, `.mp3`, `.wav` → Video/Audio file
- Local `.txt`, `.md` file or pasted text → Meeting transcript or raw text
- Ask the user if ambiguous (e.g., a `.txt` could be a transcript or notes)

### Step 2: Extract Raw Text

**YouTube videos:**
```bash
# Try subtitles first (fastest, no transcription needed)
yt-dlp --write-auto-sub --sub-lang en --skip-download --convert-subs srt -o "%(title)s" "<url>"

# If no subtitles available, download audio and transcribe
yt-dlp -x --audio-format wav -o "/tmp/ingest-audio.wav" "<url>"
whisper /tmp/ingest-audio.wav --model base --output_format txt --output_dir /tmp/
```

**Web articles:**
```bash
defuddle parse <url> --md
```

**PDFs:**
```bash
pdftotext <path> -
# or via Python: PyPDF2, pdfplumber
```

**Video/Audio files:**
```bash
whisper <path> --model base --output_format txt --output_dir /tmp/
```

**Meeting transcripts / raw text:**
- Read directly from file or accept pasted content

### Step 3: Analyze and Structure

Process the raw text through Claude to extract structured insights. Use the appropriate output format (External Content or Meeting Transcript — see Concepts above).

Guidelines:
- **Claims should be atomic** — one idea per claim, stated as a complete assertion
- **Frameworks must be named** — if the source names it, use that name; if not, create a descriptive name
- **Action items must be concrete** — "do X" not "consider X"
- **For meetings**: always capture WHO decided/owns WHAT and by WHEN

### Step 4: Generate Vault Note

Create an Obsidian note with proper frontmatter and wikilinks:

**For External Content:**

```markdown
---
type: ingested
source-type: youtube | article | pdf | audio
source-url: "<url or path>"
source-title: "<title>"
ingested: YYYY-MM-DD
claims-count: N
frameworks-count: N
action-items-count: N
tags:
  - ingested
  - <topic-tag>
---

# <Source Title>

**Source:** <url or link>
**Ingested:** YYYY-MM-DD

## Claims

1. <Atomic claim 1>
2. <Atomic claim 2>
...

## Frameworks

### <Framework Name>
<Description of the framework/mental model>

## Action Items

- [ ] <Concrete action 1>
- [ ] <Concrete action 2>

## Examples

- **<Example title>**: <Description with context>

## Key Quotes

> "<Notable quote>" — <speaker if known>

## Raw Summary

<2-3 paragraph summary of the full content>
```

**For Meeting Transcripts:**

```markdown
---
type: ingested
source-type: meeting
source-title: "<meeting name>"
meeting-date: YYYY-MM-DD
participants: [name1, name2]
ingested: YYYY-MM-DD
decisions-count: N
action-items-count: N
tags:
  - ingested
  - meeting
---

# <Meeting Name> — YYYY-MM-DD

**Participants:** <list>
**Ingested:** YYYY-MM-DD

## Summary

<2-3 paragraph summary>

## Decisions Made

1. **<Decision>** — Rationale: <why>
2. ...

## Action Items

| Owner | Action | Deadline | Status |
|-------|--------|----------|--------|
| <name> | <action> | <date> | pending |

## Key Context

- <Important background point 1>
- <Important background point 2>

## Open Questions

- <Unresolved topic 1>
- <Unresolved topic 2>
```

### Step 5: Save and Confirm

1. Save the note to `~/.canuto/vault/knowledge/ingested/<slug>.md`
   - Slug format: `YYYY-MM-DD-<short-title-kebab-case>.md`
2. Present a summary to the user:
   ```
   Ingested: <title>
   - Source: <type> — <url/path>
   - Claims: N | Frameworks: N | Action Items: N
   - Saved to: knowledge/ingested/<filename>

   Review the note? [Y/n]
   ```
3. Only save after user confirms. Allow edits before saving.

---

## Prerequisites

Depending on source type, these tools may be needed:

| Tool | For | Install |
|------|-----|---------|
| `defuddle` | Web articles | `npm install -g defuddle` |
| `yt-dlp` | YouTube videos | `pip install yt-dlp` or `brew install yt-dlp` |
| `whisper` | Audio transcription | `pip install openai-whisper` |
| `pdftotext` | PDF extraction | `apt install poppler-utils` or `brew install poppler` |

If a required tool is not installed, inform the user and offer to help install it. Never fail silently.

---

## Examples

### ✅ Good — YouTube video ingestion

```
User: "Ingest this video into the vault: https://youtube.com/watch?v=abc123"

[Agent downloads subtitles, extracts structured knowledge]

Ingested: "How to Build AI Agents" by Andrej Karpathy
- Source: youtube — https://youtube.com/watch?v=abc123
- Claims: 14 | Frameworks: 3 | Action Items: 6
- Saved to: knowledge/ingested/2026-03-23-how-to-build-ai-agents.md

Review the note? [Y/n]
```

### ✅ Good — Meeting transcript processing

```
User: "Process this call transcript: /path/to/standup-2026-03-23.txt"

[Agent reads transcript, extracts decisions and actions]

Ingested: Team Standup — 2026-03-23
- Source: meeting — /path/to/standup-2026-03-23.txt
- Decisions: 3 | Action Items: 5
- Saved to: knowledge/ingested/2026-03-23-team-standup.md

Review the note? [Y/n]
```

### ❌ Bad — Dumping raw transcript without structure

```markdown
# Meeting Notes
[Full raw transcript pasted here with no extraction]
```

This is bad because: no structured extraction, not searchable, not actionable.

---

## Guardrails

- **Never auto-save without user confirmation.** Always present the extracted content and let the user review/edit.
- **Keep claims atomic.** Each claim should be one self-contained assertion, not a paragraph.
- **Transcription stays local.** Use `whisper` locally — never send audio to external APIs without explicit user consent.
- **Don't fabricate content.** Only extract what's actually in the source. If something is unclear, mark it as `[unclear]`.
- **Reuse existing skills.** Use `defuddle` for web articles, don't reinvent web scraping.
- **Tag appropriately.** Add topic-specific tags so the note is discoverable via vault search.
- **Link to related notes.** If the ingested content relates to existing vault notes (decisions, instincts, projects), add wikilinks.
