#!/usr/bin/env bash
# =============================================================================
# Canuto Framework — Vault Analyzer
# Analyzes ~/.canuto/vault/ for cross-project patterns, metrics, and health.
#
# Usage:
#   bash analyze.sh              — Full analysis (terminal + vault report)
#   bash analyze.sh --terminal   — Terminal output only
#   bash analyze.sh --vault      — Vault report only
# =============================================================================

set -euo pipefail

VAULT="$HOME/.canuto/vault"
OUTPUT_MODE="both" # both | terminal | vault

# ── Parse args ──────────────────────────────────────────────────────────────
while [[ $# -gt 0 ]]; do
  case $1 in
    --terminal) OUTPUT_MODE="terminal" ;;
    --vault)    OUTPUT_MODE="vault" ;;
  esac
  shift
done

# ── Colors ──────────────────────────────────────────────────────────────────
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
RED='\033[0;31m'
BOLD='\033[1m'
RESET='\033[0m'

# ── Verify vault exists ────────────────────────────────────────────────────
if [ ! -d "$VAULT/projects" ]; then
  echo -e "${RED}No vault found at $VAULT${RESET}"
  echo "Run install.sh first to create the vault."
  exit 1
fi

if ! command -v python3 &> /dev/null; then
  echo -e "${RED}python3 required for analysis${RESET}"
  exit 1
fi

# ── Run analysis ────────────────────────────────────────────────────────────
REPORT=$(python3 << 'PYEOF'
import os, json, glob, sys
from datetime import datetime, timedelta
from collections import defaultdict, Counter
from pathlib import Path

vault = os.path.expanduser("~/.canuto/vault")
projects_dir = f"{vault}/projects"
today = datetime.now()

def count_files(path, ext="*.md"):
    files = glob.glob(f"{path}/{ext}")
    return len([f for f in files if '.gitkeep' not in f])

def read_frontmatter(filepath):
    """Extract YAML frontmatter as dict (simple parser)."""
    fm = {}
    try:
        with open(filepath) as f:
            lines = f.readlines()
        if not lines or lines[0].strip() != '---':
            return fm
        for line in lines[1:]:
            if line.strip() == '---':
                break
            if ':' in line:
                key, _, val = line.partition(':')
                fm[key.strip()] = val.strip()
    except:
        pass
    return fm

def file_age_days(filepath):
    try:
        mtime = os.path.getmtime(filepath)
        return (today - datetime.fromtimestamp(mtime)).days
    except:
        return -1

# ── Discover projects ─────────────────────────────────────────────────────
projects = sorted([d for d in os.listdir(projects_dir)
                   if os.path.isdir(f"{projects_dir}/{d}") and d != '.obsidian'])

report = []
report.append("# Vault Analysis Report")
report.append(f"\nDate: {today.strftime('%Y-%m-%d %H:%M')}")
report.append(f"Vault: {vault}")
report.append(f"Projects: {len(projects)}")

# ── Per-project stats ─────────────────────────────────────────────────────
report.append("\n## Project Overview\n")
report.append("| Project | Sessions | Decisions | Instincts | Pending | Metrics | Last Activity |")
report.append("|---------|----------|-----------|-----------|---------|---------|---------------|")

all_instincts = []  # (project, category, pattern, confidence, applied)
all_sessions = []   # (project, date, filepath)
project_stats = {}

for proj in projects:
    pdir = f"{projects_dir}/{proj}"
    stats = {
        'sessions': count_files(f"{pdir}/sessions"),
        'decisions': count_files(f"{pdir}/decisions"),
        'instincts': count_files(f"{pdir}/instincts"),
        'pending': count_files(f"{pdir}/pending"),
        'metrics': count_files(f"{pdir}/metrics"),
    }
    project_stats[proj] = stats

    # Find last activity
    all_md = glob.glob(f"{pdir}/**/*.md", recursive=True)
    all_md = [f for f in all_md if '.gitkeep' not in f and '_index' not in f]
    if all_md:
        newest = max(all_md, key=os.path.getmtime)
        age = file_age_days(newest)
        last_activity = f"{age}d ago" if age > 0 else "today"
    else:
        last_activity = "no activity"

    report.append(f"| {proj} | {stats['sessions']} | {stats['decisions']} | {stats['instincts']} | {stats['pending']} | {stats['metrics']} | {last_activity} |")

    # Collect instincts
    for ifile in glob.glob(f"{pdir}/instincts/*.md"):
        if '.gitkeep' in ifile:
            continue
        fm = read_frontmatter(ifile)
        all_instincts.append({
            'project': proj,
            'category': fm.get('category', 'unknown'),
            'confidence': fm.get('confidence', 'unknown'),
            'applied': int(fm.get('applied', '0') or '0'),
            'name': os.path.basename(ifile).replace('.md', ''),
            'file': ifile,
        })

    # Collect sessions
    for sfile in sorted(glob.glob(f"{pdir}/sessions/*.md")):
        if '.gitkeep' in sfile:
            continue
        sname = os.path.basename(sfile).replace('.md', '')
        all_sessions.append({'project': proj, 'date': sname, 'file': sfile})

# ── Global instincts ──────────────────────────────────────────────────────
global_instincts = []
for ifile in glob.glob(f"{vault}/global-instincts/*.md"):
    if '.gitkeep' in ifile:
        continue
    fm = read_frontmatter(ifile)
    global_instincts.append({
        'category': fm.get('category', 'unknown'),
        'confidence': fm.get('confidence', 'unknown'),
        'applied': int(fm.get('applied', '0') or '0'),
        'name': os.path.basename(ifile).replace('.md', ''),
        'source_project': fm.get('source_project', 'unknown'),
    })

# ── Cross-project patterns ───────────────────────────────────────────────
report.append("\n## Cross-Project Patterns\n")

# Group instincts by category
by_category = defaultdict(list)
for inst in all_instincts:
    by_category[inst['category']].append(inst)

repeated_categories = {cat: insts for cat, insts in by_category.items()
                       if len(set(i['project'] for i in insts)) > 1}

if repeated_categories:
    report.append("Instincts that appear in **multiple projects** (same category):\n")
    for cat, insts in sorted(repeated_categories.items()):
        projects_with = sorted(set(i['project'] for i in insts))
        report.append(f"### {cat}")
        report.append(f"Projects: {', '.join(projects_with)}\n")
        for inst in insts:
            conf_icon = {'high': '🟢', 'medium': '🟡', 'low': '🔴'}.get(inst['confidence'], '⚪')
            report.append(f"- {conf_icon} **{inst['name']}** ({inst['project']}) — confidence: {inst['confidence']}, applied: {inst['applied']}")
        report.append("")
else:
    report.append("No cross-project patterns found yet. Instincts are project-specific.\n")
    report.append("As you accumulate sessions across projects, patterns will emerge here.\n")

# ── Aggregated metrics ────────────────────────────────────────────────────
report.append("\n## Aggregated Stats\n")

total_sessions = len(all_sessions)
total_instincts = len(all_instincts)
total_global = len(global_instincts)
high_conf = len([i for i in all_instincts if i['confidence'] == 'high'])
med_conf = len([i for i in all_instincts if i['confidence'] == 'medium'])
low_conf = len([i for i in all_instincts if i['confidence'] == 'low'])

report.append(f"- **Total sessions**: {total_sessions} across {len(projects)} projects")
report.append(f"- **Total instincts**: {total_instincts} (🟢 {high_conf} high, 🟡 {med_conf} medium, 🔴 {low_conf} low)")
report.append(f"- **Global instincts**: {total_global} (promoted from projects)")
report.append(f"- **Categories**: {len(by_category)} unique categories")

# ── Abandoned projects ────────────────────────────────────────────────────
report.append("\n## Project Health\n")

for proj in projects:
    pdir = f"{projects_dir}/{proj}"
    all_md = glob.glob(f"{pdir}/**/*.md", recursive=True)
    all_md = [f for f in all_md if '.gitkeep' not in f and '_index' not in f]
    if all_md:
        newest = max(all_md, key=os.path.getmtime)
        age = file_age_days(newest)
        if age > 30:
            report.append(f"- ⚠️ **{proj}**: no activity for {age} days — consider archiving")
        elif age > 7:
            report.append(f"- 🟡 **{proj}**: last activity {age} days ago")
        else:
            report.append(f"- 🟢 **{proj}**: active (last activity {age}d ago)")
    else:
        report.append(f"- ⚪ **{proj}**: empty (no notes)")

# ── Promotion candidates ─────────────────────────────────────────────────
report.append("\n## Promotion Candidates\n")
report.append("Instincts with high confidence that could be promoted to global:\n")

candidates = [i for i in all_instincts if i['confidence'] == 'high']
if candidates:
    for inst in sorted(candidates, key=lambda x: x['applied'], reverse=True):
        # Check if already in global
        already_global = any(g['name'] == inst['name'] for g in global_instincts)
        status = " (already global)" if already_global else ""
        report.append(f"- **{inst['name']}** from {inst['project']} — applied {inst['applied']} times{status}")
else:
    report.append("No high-confidence instincts found yet. Keep using the framework!")

# ── Session timeline ──────────────────────────────────────────────────────
report.append("\n## Recent Sessions\n")

recent = sorted(all_sessions, key=lambda x: x['date'], reverse=True)[:10]
if recent:
    report.append("| Date | Project |")
    report.append("|------|---------|")
    for s in recent:
        report.append(f"| {s['date']} | {s['project']} |")
else:
    report.append("No sessions recorded yet.")

# ── Output ────────────────────────────────────────────────────────────────
print('\n'.join(report))
PYEOF
)

# ── Terminal output ─────────────────────────────────────────────────────────
if [ "$OUTPUT_MODE" != "vault" ]; then
  echo ""
  echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
  echo -e "${CYAN}  Canuto — Vault Analysis${RESET}"
  echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
  echo ""
  echo "$REPORT"
  echo ""
fi

# ── Vault report ────────────────────────────────────────────────────────────
if [ "$OUTPUT_MODE" != "terminal" ]; then
  REPORT_DIR="$VAULT/reports"
  mkdir -p "$REPORT_DIR"
  REPORT_FILE="$REPORT_DIR/$(date +%Y-%m-%d)-analysis.md"

  # Add frontmatter
  cat > "$REPORT_FILE" << FMEOF
---
title: Vault Analysis $(date +%Y-%m-%d)
date: $(date +%Y-%m-%d)
tags:
  - report
  - analysis
type: vault-analysis
---

FMEOF
  echo "$REPORT" >> "$REPORT_FILE"
  echo -e "${GREEN}[canuto]${RESET} ✓ Report saved: $REPORT_FILE"
fi
