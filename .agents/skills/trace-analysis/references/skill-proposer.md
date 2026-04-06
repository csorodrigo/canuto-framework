# Skill Proposer Checklist

Trigger this reference when `trace-analysis` classifies a **skill-gap** signal. The goal is to detect when a recurring workflow deserves its own skill file (often to automate multi-step procedures).

## Detection Rules
1. **Repeated user commands** — If audit logs for 3+ sessions show the same CLI sequence (e.g., `rg` → `sed` → `apply_patch`), treat as candidate automation.
2. **Recurring prompts** — Session notes with similar "What Was Done" phrasing (matching bigrams) across ≥3 sessions.
3. **Manual multi-step workflows** — Maestro orchestrates identical persona sequences to achieve the same fix at least twice (e.g., Architect + Coder loop just to regenerate configs).

## Proposal Steps
1. Gather evidence (session IDs, audit file lines, metrics).
2. Describe the workflow in 3 bullets: Trigger, Steps today, Cost (time/rework).
3. Suggest scope: new standalone skill vs. addition to existing skill.
4. Present to user for approval. On approval, call existing `skill-creator` workflow with:
   - Intent summary
   - Required personas
   - Input/Output expectations

## Template Snippet
```
Skill Candidate: Vault sync fixer
Evidence: sessions/2026-03-31, 2026-04-02, 2026-04-04
Trigger: Reviewer requests "sync obsidian indexes"
Current steps: run `.agents/tools/vault-sync.sh`, verify, re-run tests
Cost: 18 minutes + 2 reruns per session
Proposal: Add `vault-sync` skill invoked by Maestro before Reviewer starts.
```

Keep proposals lightweight; approval + actual skill creation still gated by the user.
