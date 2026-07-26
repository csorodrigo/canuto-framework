---
skill: notebooklm
trigger: /notebooklm
persona: maestro
version: 0.1.0
plugin: notebooklm
---

# NotebookLM Skill

Orchestrate Google NotebookLM from within the framework: automated source discovery, podcast generation, artifact export, and RAG over documents.

---

## When to Use

| User intent | Action |
|-------------|--------|
| "faz pesquisa automática sobre X" | Research Mode |
| "transforma em podcast" / "gera áudio" | Audio Overview |
| "cria um report / study guide / slide deck" | Artifact Generation |
| "pergunta sobre os documentos" | Chat/RAG |
| "adiciona essa URL / PDF ao notebook" | Source Management |

---

## Prerequisites

Verify before any operation:

```bash
notebooklm status
```

If auth is expired:
```bash
notebooklm login   # Google OAuth via browser
```

---

## 1. Notebook Management

```bash
# List notebooks
notebooklm list --json

# Create notebook for a project/topic
notebooklm create "Pesquisa: {tema}"

# Set active notebook for this session
notebooklm use <notebook_id>

# Get summary of active notebook
notebooklm summary
```

If CLAUDE.md has `notebooklm.default_notebook_id`, use that automatically with `notebooklm use`.

---

## 2. Research Mode (descoberta automática de fontes)

Use when the user wants AI-powered source discovery from the web or Google Drive.

### Fast research (blocking — for quick queries)
```bash
notebooklm source add-research "{query}" --mode fast
```

### Deep research (async — for thorough exploration)
```bash
# Start non-blocking
notebooklm source add-research "{query}" --mode deep --no-wait

# Do other work while research runs, then:
notebooklm research wait --import-all

# Or check status manually
notebooklm research status --json
```

### Drive research
```bash
notebooklm source add-research "{query}" --from drive --mode deep
```

### Integration with Canuto research.md
After research completes and sources are imported, save key findings to vault:
```bash
# Ask for key insights and save as NotebookLM note (shows up in `note list`)
notebooklm ask "Quais são os principais insights sobre {query}?" --save-as-note

# Then ingest the note content into Obsidian vault via knowledge-ingest skill
```

---

## 3. Audio Overviews (podcasts)

Use when the user wants to generate a listenable summary.

### Generate from active notebook sources
```bash
notebooklm generate audio --wait
notebooklm download audio ./output/overview.mp3
```

### With specific focus instruction
```bash
notebooklm generate audio "Foque nas decisões de arquitetura e seus trade-offs" --wait
notebooklm download audio ./output/architecture-decisions.mp3
```

### Workflow: Session Podcast
To convert a session note into a podcast:
1. Get session note content from vault
2. Add as source:
   ```bash
   notebooklm source add "{session_note_content}" --title "Session {YYYY-MM-DD}"
   ```
3. Generate audio:
   ```bash
   notebooklm generate audio "Resumo das decisões e aprendizados desta sessão" --wait
   notebooklm download audio ./session-{YYYY-MM-DD}.mp3
   ```
4. Update session note frontmatter with `audio_overview` key pointing to the file.

---

## 4. Artifact Generation

Use when the user needs a structured deliverable.

### Report (briefing doc / study guide)
```bash
notebooklm generate report "{instrução opcional}" --wait
notebooklm download report ./output/report.md
```

### Mind Map
```bash
notebooklm generate mind-map --wait
notebooklm download mind-map ./output/mind-map.json
```

### Slide Deck
```bash
notebooklm generate slide-deck --wait
notebooklm download slide-deck ./output/slides.pptx
```

### Quiz (for knowledge review)
```bash
notebooklm generate quiz --wait
notebooklm download quiz ./output/quiz.json
```

### Flashcards
```bash
notebooklm generate flashcards --wait
notebooklm download flashcards ./output/flashcards.json
```

### Data Table
```bash
notebooklm generate data-table --wait
notebooklm download data-table ./output/data.csv
```

### Infographic
```bash
notebooklm generate infographic --wait
notebooklm download infographic ./output/infographic.png
```

### Polling for async generation
All `generate` commands support `--wait`. For manual async:
```bash
notebooklm generate report --no-wait     # returns task_id
notebooklm artifact poll <artifact_id>
notebooklm artifact wait <artifact_id>   # blocks until ready
```

---

## 5. Chat / RAG over Sources

Use when the user wants to query the notebook's document corpus.

```bash
# Ask a question (RAG with inline citations)
notebooklm ask "Quais são os principais trade-offs arquiteturais discutidos?"

# Ask and save answer as a NotebookLM note
notebooklm ask "Qual decisão foi tomada sobre autenticação?" --save-as-note

# Restrict to specific sources
notebooklm ask "Resumo desta fonte" -s <source_id>

# View conversation history
notebooklm history --json
```

---

## 6. Source Management

```bash
# Add URL
notebooklm source add "https://exemplo.com/artigo"

# Add local file (PDF, DOCX, CSV, Markdown, image)
notebooklm source add ./docs/spec.pdf
notebooklm source add ./research/paper.docx

# Add YouTube video
notebooklm source add "https://youtube.com/watch?v=..."

# Add inline text
notebooklm source add "Conteúdo aqui" --title "Título descritivo"

# Add from Google Drive (requires Drive auth)
notebooklm source add-drive <file_id> --title "Nome do arquivo"

# List all sources
notebooklm source list --json

# Get full indexed text of a source
notebooklm source fulltext <source_id>

# Refresh a source (re-fetch URL content)
notebooklm source refresh <source_id>

# Delete a source
notebooklm source delete <source_id>
```

---

## 7. Notes Management

NotebookLM notes are different from Obsidian vault notes — they live inside the notebook.

```bash
# List notes
notebooklm note list --json

# Get note content
notebooklm note get <note_id>

# Create a note
notebooklm note create "Título" "Conteúdo da nota"

# Save current chat answer as note
notebooklm ask "pergunta" --save-as-note
```

---

## Output Conventions

- Use `--json` flag for all list/status commands when parsing results programmatically
- Save generated artifacts to `./output/` or a path specified by the user
- After generating artifacts, present the file path to the user
- Log significant operations (research start/complete, audio generated) as vault audit events when the audit-trail skill is active

---

## Common Patterns with Canuto Framework

### Pattern 1: Research enrichment
```
research.md Phase 0 (community intelligence)
  ↓
notebooklm source add-research "{query}" --mode deep --no-wait
  ↓
research.md Phase 1-2 (manual analysis runs in parallel)
  ↓
notebooklm research wait --import-all
  ↓
notebooklm ask "síntese dos achados" --save-as-note
  ↓
knowledge-ingest.md (salvar no vault Obsidian)
```

### Pattern 2: Feature briefing deliverable
```
feature developed + reviewed
  ↓
notebooklm source add "{feature spec + context}" --title "Feature: {nome}"
  ↓
notebooklm generate report "Briefing técnico para stakeholders" --wait
  ↓
notebooklm download report ./docs/feature-{nome}-briefing.md
```

### Pattern 3: Session podcast
```
session ends → session note written to vault
  ↓
notebooklm source add "{session note content}" --title "Session {data}"
  ↓
notebooklm generate audio "Decisões e aprendizados da sessão" --wait
  ↓
notebooklm download audio ./.agents/vault/sessions/audio/{data}.mp3
  ↓
update session note frontmatter: audio_overview: "{path}"
```

---

## Troubleshooting

| Error | Fix |
|-------|-----|
| `401 Unauthorized` | `notebooklm login` |
| `Rate limit exceeded` | Aguardar ~1h ou upgrade para Google One AI Premium |
| `Source processing failed` | Verificar formato do arquivo; tentar `source refresh` |
| `Generation timeout` | Tentar novamente; usar `--no-wait` + `artifact poll` |
| `API changed` | Atualizar: `pip install --upgrade notebooklm-py` |
