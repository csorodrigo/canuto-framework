---
skill: codex-onboarding
trigger: On fresh install (install.sh), or /codex-onboard for new projects
persona: contextualizer
version: 1.0.0
lastUpdated: 2026-03-30
shortDescription: >
  Codex runs auto-analysis on new projects instead of Opus. Generates
  project-index.json and onboarding-report.md via spawn_agent. Opus-free onboarding.
usedBy: [contextualizer, maestro]
evals:
  - prompt: "onboard this new project with codex"
    should_trigger: true
  - prompt: "run auto-analysis"
    should_trigger: true
  - prompt: "plan the next feature"
    should_trigger: false
---

## Purpose

The `post_install_analysis()` in install.sh generates project-index.json using
Python. For deeper analysis (architecture patterns, domain detection, cross-project
comparison), delegate to Codex which can read files and reason about them.

**Opus-free onboarding** — Codex does all the heavy reading.

---

## Procedure

### 1. Basic Index (install.sh)

`post_install_analysis()` generates the initial `project-index.json` with
stack detection, dependencies, file structure. This runs in Python (fast, no API cost).

### 2. Deep Analysis (Codex)

For richer onboarding, spawn Codex:

```
codex exec --profile coder({
  prompt: `
You are onboarding a new project. Generate a comprehensive analysis.

## Instructions
1. Read project-index.json for basic stack info
2. Read key source directories (src/, lib/, app/)
3. Read .context.md files if they exist
4. Read CLAUDE.md and AGENTS.md for project rules

## Generate
Write the following files:

### .agents/tmp/onboarding-report.md
- Project overview (what it does, for whom)
- Architecture summary (patterns, layers, data flow)
- Key modules and their responsibilities
- Testing strategy (framework, coverage approach)
- Deployment setup (if detectable)
- Potential complexity areas (large files, deep nesting)
- Suggested first tasks for a new developer

### .agents/vault/digests/ (one per key directory)
- Generate digests for top-level source directories
- Follow the digest format from context-digest skill

### .agents/tmp/context-package.md
- Pre-loaded context for future Codex tasks
- Include all digests and key types

## Rules
- Be factual — only describe what you see, don't speculate
- Note any .env.example vars that need configuration
- Flag any obvious security concerns
`
})
```

### 3. Opus Reviews Summary

Read `.agents/tmp/onboarding-report.md` (small file) and present
key findings to the user. Opus hasn't read any source files.

---

## install.sh Integration

After `post_install_analysis()`, optionally run Codex deep analysis:
```bash
if command -v codex &>/dev/null && [ -t 0 ]; then
  read -r -p "Run Codex deep analysis? [Y/n] " DEEP_ANSWER
  # If yes, note that this requires an active Claude session
  # The skill is triggered from within Claude, not from bash
fi
```

---

## Integration

- **auto-analysis.md**: existing skill, this is the Codex-delegated version
- **context-digest.md**: Codex generates digests during onboarding
- **context-preload.md**: onboarding creates initial context package
- **canuto-init.md**: onboarding sequence includes this step
