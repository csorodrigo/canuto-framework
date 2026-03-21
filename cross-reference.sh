#!/usr/bin/env bash
# =============================================================================
# Canuto Framework — Cross-Reference Engine
# Cruza soluções entre projetos no vault.
#
# Usage:
#   bash cross-reference.sh                  — Full analysis (terminal + vault)
#   bash cross-reference.sh --terminal       — Terminal only
#   bash cross-reference.sh --project slug   — Focus on specific project
# =============================================================================

set -euo pipefail

VAULT="$HOME/.canuto/vault"
OUTPUT_MODE="both"
FOCUS_PROJECT=""

while [[ $# -gt 0 ]]; do
  case $1 in
    --terminal) OUTPUT_MODE="terminal" ;;
    --vault)    OUTPUT_MODE="vault" ;;
    --project)  FOCUS_PROJECT="$2"; shift ;;
  esac
  shift
done

# ── Verify ──────────────────────────────────────────────────────────────────
if [ ! -d "$VAULT/projects" ]; then
  echo -e "\033[0;31m[canuto]\033[0m No vault found at $VAULT"
  exit 1
fi

if ! command -v python3 &> /dev/null; then
  echo -e "\033[0;31m[canuto]\033[0m python3 required"
  exit 1
fi

# ── Run ─────────────────────────────────────────────────────────────────────
REPORT=$(FOCUS="$FOCUS_PROJECT" CANUTO_VAULT="$VAULT" python3 << 'PYEOF'
import os, json, glob, sys
from datetime import datetime
from collections import defaultdict, Counter

vault = os.environ.get("CANUTO_VAULT", os.path.expanduser("~/.canuto/vault"))
projects_dir = f"{vault}/projects"
focus = os.environ.get("FOCUS", "")
today = datetime.now()

def _safe_int(val, default=0):
    try:
        return int(val or default)
    except (ValueError, TypeError):
        return default

def read_frontmatter(filepath):
    """Extract YAML frontmatter and first heading from a markdown note.
    Handles values with colons (e.g., URLs)."""
    fm = {}
    try:
        with open(filepath, errors='ignore') as f:
            lines = f.readlines()
        if not lines or lines[0].strip() != '---':
            return fm
        # Parse frontmatter
        for line in lines[1:]:
            if line.strip() == '---':
                break
            if ':' in line:
                key, _, val = line.partition(':')
                key = key.strip()
                val = val.strip().strip('"')
                if key and not key.startswith('#') and not key.startswith('-'):
                    fm[key] = val
        # Grab first heading after frontmatter as title
        found_end = 0
        for line in lines[1:]:
            if line.strip() == '---':
                found_end += 1
                continue
            if found_end >= 1 and line.startswith('# '):
                fm['_title'] = line.lstrip('# ').strip()
                break
    except (IOError, OSError) as e:
        print(f"Warning: could not read {filepath}: {e}", file=sys.stderr)
    return fm

# ── Load all project indexes ─────────────────────────────────────────
projects = {}
for p in sorted(os.listdir(projects_dir)):
    pdir = f"{projects_dir}/{p}"
    if not os.path.isdir(pdir) or p == '.obsidian':
        continue
    idx_path = f"{pdir}/project-index.json"
    # Skip projects without index (per spec: unindexed projects are excluded)
    if not os.path.exists(idx_path):
        continue
    try:
        with open(idx_path) as f:
            idx = json.load(f)
    except (json.JSONDecodeError, IOError, OSError) as e:
        print(f"Warning: skipping {p} (bad project-index.json): {e}", file=sys.stderr)
        continue
    projects[p] = {
        "index": idx,
        "instincts": [],
        "decisions": [],
        "sessions_count": len([f for f in glob.glob(f"{pdir}/sessions/*.md") if '.gitkeep' not in f]),
    }

    # Load instincts
    for ifile in glob.glob(f"{pdir}/instincts/*.md"):
        if '.gitkeep' in ifile: continue
        fm = read_frontmatter(ifile)
        projects[p]["instincts"].append({
            "name": os.path.basename(ifile).replace('.md', ''),
            "title": fm.get('_title', fm.get('id', 'unknown')),
            "category": fm.get('category', 'unknown'),
            "confidence": fm.get('confidence', 'unknown'),
            "applied": _safe_int(fm.get('applied', '0')),
        })

    # Load decisions
    for dfile in glob.glob(f"{pdir}/decisions/*.md"):
        if '.gitkeep' in dfile or 'migrated' in dfile: continue
        fm = read_frontmatter(dfile)
        projects[p]["decisions"].append({
            "name": os.path.basename(dfile).replace('.md', ''),
            "title": fm.get('_title', fm.get('id', 'unknown')),
            "domain": fm.get('domain', 'unknown'),
            "status": fm.get('status', 'unknown'),
        })

report = []
report.append("# Cross-Project Solution Map")
report.append(f"\nDate: {today.strftime('%Y-%m-%d %H:%M')}")
report.append(f"Projects analyzed: {len(projects)}")

# ── Stack Clusters ───────────────────────────────────────────────────
report.append("\n## Stack Clusters\n")

clusters = defaultdict(list)
for slug, data in projects.items():
    idx = data["index"]
    stack = idx.get("stack", {})
    lang = stack.get("primary_language", "unknown")
    fw = stack.get("framework", "none")
    cluster_key = f"{lang}/{fw}" if fw != "none" else lang
    clusters[cluster_key].append(slug)

if clusters:
    report.append("| Cluster | Projects | Count |")
    report.append("|---------|----------|-------|")
    for cluster, slugs in sorted(clusters.items(), key=lambda x: len(x[1]), reverse=True):
        report.append(f"| {cluster} | {', '.join(slugs)} | {len(slugs)} |")
else:
    report.append("No indexed projects found. Run `install.sh` with auto-analysis in each project.")
report.append("")

# ── Shared Dependencies ──────────────────────────────────────────────
report.append("## Shared Dependencies\n")

dep_projects = defaultdict(list)
for slug, data in projects.items():
    idx = data["index"]
    all_deps = set(idx.get("dependencies", {}).get("production", {}).keys())
    for dep in all_deps:
        dep_projects[dep].append(slug)

# Filter to deps in 2+ projects
shared = {dep: slugs for dep, slugs in dep_projects.items() if len(slugs) > 1}
if shared:
    report.append("| Dependency | Projects | Count |")
    report.append("|-----------|----------|-------|")
    for dep, slugs in sorted(shared.items(), key=lambda x: len(x[1]), reverse=True)[:20]:
        report.append(f"| {dep} | {', '.join(slugs)} | {len(slugs)} |")
else:
    report.append("No shared dependencies found across projects.")
report.append("")

# ── Cross-Project Instinct Patterns ──────────────────────────────────
report.append("## Instinct Patterns Across Projects\n")

by_category = defaultdict(list)
for slug, data in projects.items():
    for inst in data["instincts"]:
        by_category[inst["category"]].append({"project": slug, **inst})

cross_patterns = {cat: insts for cat, insts in by_category.items()
                  if len(set(i["project"] for i in insts)) > 1}

if cross_patterns:
    report.append("Categories with instincts in **multiple projects**:\n")
    for cat, insts in sorted(cross_patterns.items()):
        project_list = sorted(set(i["project"] for i in insts))
        report.append(f"### {cat}")
        report.append(f"Projects: {', '.join(project_list)}\n")
        for inst in sorted(insts, key=lambda x: x["applied"], reverse=True):
            icon = {'high': '🟢', 'medium': '🟡', 'low': '🔴'}.get(inst["confidence"], '⚪')
            report.append(f"- {icon} [{inst['project']}] **{inst['title']}** — {inst['confidence']}, applied {inst['applied']}x")
        report.append("")
else:
    report.append("No cross-project patterns found yet.\n")

# ── Solution Transfer Opportunities ──────────────────────────────────
report.append("## Solution Transfer Opportunities\n")

# Find projects with high-confidence instincts that could help other projects
# in the same category where other projects only have low/no instincts
transfers = []
for cat, insts in by_category.items():
    by_proj = defaultdict(list)
    for inst in insts:
        by_proj[inst["project"]].append(inst)

    # Find projects with high instincts
    high_projects = {p: i for p, il in by_proj.items()
                     for i in il if i["confidence"] == "high"}
    # Find projects with low or no instincts in same category
    low_projects = {p for p, il in by_proj.items()
                    if all(i["confidence"] in ("low", "unknown") for i in il)}
    # All other projects that DON'T have this category at all
    no_projects = set(projects.keys()) - set(by_proj.keys())

    for source_proj, inst in high_projects.items():
        for target in (low_projects | no_projects):
            if target == source_proj: continue
            # Check stack compatibility
            src_idx = projects[source_proj]["index"]
            tgt_idx = projects[target]["index"]
            src_lang = src_idx.get("stack", {}).get("primary_language", "")
            tgt_lang = tgt_idx.get("stack", {}).get("primary_language", "")
            if src_lang == tgt_lang or not tgt_lang:
                transfers.append({
                    "source": source_proj,
                    "target": target,
                    "instinct": inst["title"],
                    "category": cat,
                    "applied": inst["applied"],
                })

if transfers:
    transfers.sort(key=lambda t: t["applied"], reverse=True)
    for t in transfers[:15]:
        report.append(f"- **{t['source']}** solved \"{t['instinct']}\" ({t['category']}) → could help **{t['target']}** (applied {t['applied']}x)")
    report.append("")
else:
    report.append("No transfer opportunities found yet. Accumulate more sessions and instincts.\n")

# ── Decision Domains Map ─────────────────────────────────────────────
report.append("## Decisions by Domain\n")

domain_decisions = defaultdict(list)
for slug, data in projects.items():
    for dec in data["decisions"]:
        domain_decisions[dec["domain"]].append({"project": slug, **dec})

cross_domains = {d: decs for d, decs in domain_decisions.items()
                 if len(set(dc["project"] for dc in decs)) > 1}

if cross_domains:
    for domain, decs in sorted(cross_domains.items()):
        report.append(f"### {domain}")
        for dec in decs:
            report.append(f"- [{dec['project']}] {dec['title']} (status: {dec['status']})")
        report.append("")
elif domain_decisions:
    report.append("All decisions are currently project-specific. Cross-domain decisions will appear as projects accumulate.\n")
else:
    report.append("No decisions recorded yet.\n")

# ── Focus project details ────────────────────────────────────────────
if focus and focus in projects:
    report.append(f"## Focus: {focus}\n")
    data = projects[focus]
    idx = data["index"]

    # Find most similar project
    my_deps = set(idx.get("dependencies", {}).get("production", {}).keys())
    best_match = None
    best_score = 0
    for slug, other in projects.items():
        if slug == focus: continue
        other_deps = set(other["index"].get("dependencies", {}).get("production", {}).keys())
        if not my_deps and not other_deps: continue
        score = len(my_deps & other_deps) / max(len(my_deps | other_deps), 1)
        if score > best_score:
            best_score = score
            best_match = slug

    if best_match:
        report.append(f"Most similar project: **{best_match}** ({round(best_score*100)}% dep match)\n")

    # Instincts from similar projects that this project doesn't have
    my_categories = set(i["category"] for i in data["instincts"])
    report.append("### Missing instinct categories (found in other projects):\n")
    missing = set(by_category.keys()) - my_categories
    if missing:
        for cat in sorted(missing):
            insts = by_category[cat]
            high = [i for i in insts if i["confidence"] == "high"]
            if high:
                report.append(f"- **{cat}**: {high[0]['title']} (from {high[0]['project']})")
    else:
        report.append("All categories covered!")
    report.append("")

# ── Summary ──────────────────────────────────────────────────────────
report.append("## Summary\n")
total_instincts = sum(len(d["instincts"]) for d in projects.values())
total_decisions = sum(len(d["decisions"]) for d in projects.values())
total_sessions = sum(d["sessions_count"] for d in projects.values())
report.append(f"- **{len(projects)}** projects indexed")
report.append(f"- **{total_sessions}** total sessions")
report.append(f"- **{total_instincts}** instincts ({len(cross_patterns)} cross-project categories)")
report.append(f"- **{total_decisions}** decisions ({len(cross_domains)} cross-project domains)")
report.append(f"- **{len(shared)}** shared dependencies")
report.append(f"- **{len(transfers)}** solution transfer opportunities")

print('\n'.join(report))
PYEOF
)

# ── Terminal output ─────────────────────────────────────────────────────────
# Detect TTY for color support
if [ -t 1 ]; then
  CYAN='\033[0;36m'
  GREEN='\033[0;32m'
  RESET='\033[0m'
else
  CYAN=''
  GREEN=''
  RESET=''
fi

if [ "$OUTPUT_MODE" != "vault" ]; then
  echo ""
  echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
  echo -e "${CYAN}  Canuto — Cross-Reference Engine${RESET}"
  echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
  echo ""
  echo "$REPORT"
  echo ""
fi

# ── Vault report ────────────────────────────────────────────────────────────
if [ "$OUTPUT_MODE" != "terminal" ]; then
  REPORT_DIR="$VAULT/reports"
  mkdir -p "$REPORT_DIR"
  REPORT_FILE="$REPORT_DIR/cross-reference-$(date +%Y-%m-%d).md"

  cat > "$REPORT_FILE" << FMEOF
---
title: Cross-Reference $(date +%Y-%m-%d)
date: $(date +%Y-%m-%d)
tags:
  - report
  - cross-reference
type: cross-reference
---

FMEOF
  echo "$REPORT" >> "$REPORT_FILE"
  echo -e "${GREEN}[canuto]${RESET} Report saved: $REPORT_FILE"
fi
