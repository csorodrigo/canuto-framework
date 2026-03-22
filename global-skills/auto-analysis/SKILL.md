---
name: auto-analysis
description: Deep project scan + cross-reference com outros projetos no vault. Gera project-index.json e onboarding-report.md.
type: global-skill
version: 1.0.0
lastUpdated: 2026-03-22
copyright: Rodrigo Canuto © 2026
---

# /auto-analysis — Cross-Project Intelligence

Analisa o projeto atual em profundidade e cruza com todos os outros projetos indexados no vault Canuto.

## Quando Usar

- Ao instalar o Canuto num projeto novo (oferecido automaticamente)
- On-demand: `/auto-analysis` a qualquer momento
- Quando `project-index.json` estiver desatualizado (>30 dias)

---

## Protocolo

### Fase 1 — Deep Project Scan → `project-index.json`

Execute o script de análise embutido no `install.sh` (função `post_install_analysis()`).

O script Python que deve ser executado está disponível no repositório do framework. Para rodar, execute:

```bash
cd "<diretório-do-projeto-atual>"
PROJECT_DIR="$(pwd)" python3 -c "
$(cat << 'PYINLINE'
import os, sys, json, glob, re
from pathlib import Path
from datetime import datetime
from collections import defaultdict, Counter

project_dir = os.environ.get('PROJECT_DIR', os.getcwd())
project_slug = os.path.basename(os.path.abspath(project_dir))
vault = os.environ.get('CANUTO_VAULT', os.path.expanduser('~/.canuto/vault'))
project_vault = f'{vault}/projects/{project_slug}'
today = datetime.now().isoformat()[:19]

MAX_FILE_SIZE = 1_000_000
MAX_SCAN_FILES = 500

def _warn(msg):
    print(f'[canuto] {msg}', file=sys.stderr)

def _safe_read(filepath, max_size=MAX_FILE_SIZE):
    try:
        if os.path.getsize(filepath) > max_size:
            return None
        with open(filepath, errors='ignore') as f:
            return f.read()
    except (IOError, OSError):
        return None

def _safe_int(val, default=0):
    try:
        return int(val or default)
    except (ValueError, TypeError):
        return default

index = {
    'slug': project_slug, 'path': project_dir, 'last_scanned': today,
    'stack': {}, 'dependencies': {'production': {}, 'development': {}},
    'structure': {}, 'domains': [], 'patterns_detected': [],
    'ci': {'has_ci': False}, 'scripts': {}, 'env_vars': [], 'api_surface': {}
}

# Stack detection
pkg_json = f'{project_dir}/package.json'
pyproject = f'{project_dir}/pyproject.toml'
requirements = f'{project_dir}/requirements.txt'
go_mod = f'{project_dir}/go.mod'
cargo_toml = f'{project_dir}/Cargo.toml'

if os.path.exists(pkg_json):
    try:
        with open(pkg_json) as f:
            pkg = json.load(f)
        prod_deps = pkg.get('dependencies', {})
        dev_deps = pkg.get('devDependencies', {})
        all_deps = {**prod_deps, **dev_deps}
        index['dependencies']['production'] = prod_deps
        index['dependencies']['development'] = dev_deps
        has_ts = 'typescript' in dev_deps or os.path.exists(f'{project_dir}/tsconfig.json')
        index['stack']['primary_language'] = 'typescript' if has_ts else 'javascript'
        langs = ['javascript']
        if has_ts: langs.insert(0, 'typescript')
        index['stack']['languages'] = langs
        index['stack']['runtime'] = 'node'
        frameworks = {'next': 'next', 'nuxt': 'nuxt', 'express': 'express', 'fastify': 'fastify', 'koa': 'koa', 'nest': '@nestjs/core', 'remix': '@remix-run/react', 'astro': 'astro'}
        for name, dep in frameworks.items():
            if dep in all_deps:
                index['stack']['framework'] = name
                break
        ui_fws = {'react': 'react', 'vue': 'vue', 'svelte': 'svelte', 'solid': 'solid-js'}
        for name, dep in ui_fws.items():
            if dep in all_deps:
                index['stack']['ui_framework'] = name
                break
        orms = {'prisma': 'prisma', 'typeorm': 'typeorm', 'sequelize': 'sequelize', 'drizzle': 'drizzle-orm', 'mongoose': 'mongoose', 'knex': 'knex'}
        for name, dep in orms.items():
            if dep in all_deps:
                index['stack']['orm'] = name
                break
        test_fws = {'vitest': 'vitest', 'jest': 'jest', 'mocha': 'mocha', 'playwright': '@playwright/test', 'cypress': 'cypress'}
        for name, dep in test_fws.items():
            if dep in all_deps:
                index['stack']['test_framework'] = name
                break
        bundlers = {'vite': 'vite', 'webpack': 'webpack', 'esbuild': 'esbuild', 'rollup': 'rollup', 'tsup': 'tsup'}
        for name, dep in bundlers.items():
            if dep in all_deps:
                index['stack']['bundler'] = name
                break
        if os.path.exists(f'{project_dir}/pnpm-lock.yaml'): index['stack']['package_manager'] = 'pnpm'
        elif os.path.exists(f'{project_dir}/yarn.lock'): index['stack']['package_manager'] = 'yarn'
        elif os.path.exists(f'{project_dir}/bun.lockb'): index['stack']['package_manager'] = 'bun'
        else: index['stack']['package_manager'] = 'npm'
        index['scripts'] = pkg.get('scripts', {})
    except Exception as e:
        _warn(f'Could not parse package.json: {e}')
elif os.path.exists(pyproject):
    index['stack']['primary_language'] = 'python'
    index['stack']['languages'] = ['python']
    index['stack']['runtime'] = 'python'
elif os.path.exists(go_mod):
    index['stack']['primary_language'] = 'go'
    index['stack']['languages'] = ['go']
    index['stack']['runtime'] = 'go'
elif os.path.exists(cargo_toml):
    index['stack']['primary_language'] = 'rust'
    index['stack']['languages'] = ['rust']
    index['stack']['runtime'] = 'rust'

# Structure analysis
IGNORE = {'.git', 'node_modules', '.next', 'dist', 'build', '__pycache__', '.venv', 'venv', 'target', '.agents', '.obsidian', 'vendor', 'coverage'}
SOURCE_EXTS = {'.ts', '.tsx', '.js', '.jsx', '.py', '.go', '.rs', '.java', '.kt', '.rb', '.php', '.swift'}
TEST_PATTERNS = {'test', 'spec', '__tests__', 'tests', '_test'}
source_files, test_files, config_files = [], [], []
source_dirs, test_dirs = set(), set()
total_loc = source_loc = test_loc = 0

for root, dirs, files in os.walk(project_dir):
    dirs[:] = [d for d in dirs if d not in IGNORE]
    for fname in files:
        fpath = os.path.join(root, fname)
        rel_path = os.path.relpath(fpath, project_dir)
        ext = Path(fname).suffix
        if ext in SOURCE_EXTS:
            try:
                lc = sum(1 for _ in open(fpath, errors='ignore')) if os.path.getsize(fpath) <= MAX_FILE_SIZE else 0
            except: lc = 0
            is_test = any(p in rel_path.lower() for p in TEST_PATTERNS)
            if is_test:
                test_files.append(rel_path); test_dirs.add(os.path.dirname(rel_path)+'/'); test_loc += lc
            else:
                source_files.append(rel_path); source_dirs.add(os.path.dirname(rel_path)+'/'); source_loc += lc
            total_loc += lc
        elif ext in {'.json','.yaml','.yml','.toml','.ini','.env'} or fname.startswith('.env'):
            config_files.append(rel_path)

entry_candidates = ['src/index.ts','src/index.js','src/main.ts','src/main.py','src/app.ts','src/app.py','main.go','src/main.rs','src/server.ts','src/server.js','app.py','manage.py','index.ts','index.js']
entry_points = [e for e in entry_candidates if os.path.exists(f'{project_dir}/{e}')]
index['structure'] = {
    'entry_points': entry_points, 'source_dirs': sorted(list(source_dirs))[:20],
    'test_dirs': sorted(list(test_dirs))[:10], 'config_files': sorted(config_files)[:15],
    'loc': {'total': total_loc, 'source': source_loc, 'test': test_loc},
    'file_count': {'total': len(source_files)+len(test_files)+len(config_files), 'source': len(source_files), 'test': len(test_files), 'config': len(config_files)}
}

# Domain detection
domain_keywords = {
    'auth': ['auth','login','signup','jwt','token','session','oauth','password'],
    'api': ['route','controller','endpoint','handler','middleware','api'],
    'data': ['model','schema','migration','repository','database','db','prisma','orm'],
    'payments': ['payment','billing','stripe','invoice','subscription','checkout'],
    'notifications': ['notification','email','sms','push','mailer'],
    'storage': ['upload','storage','s3','bucket','file','media','image'],
    'admin': ['admin','dashboard','backoffice','panel'],
    'testing': ['test','spec','mock','fixture','factory','seed'],
    'config': ['config','env','settings','constants'],
    'ui': ['component','page','layout','view','template','widget'],
}
domain_files_map = defaultdict(list)
for sf in source_files:
    sf_lower = sf.lower()
    for domain, keywords in domain_keywords.items():
        if any(kw in sf_lower for kw in keywords):
            domain_files_map[domain].append(sf)
            break
domains = []
for domain, files in domain_files_map.items():
    confidence = min(0.5 + len(files) * 0.1, 1.0)
    domains.append({'name': domain, 'files': files[:10], 'deps': [], 'confidence': round(confidence, 2)})
index['domains'] = sorted(domains, key=lambda d: d['confidence'], reverse=True)

# Pattern detection
patterns = []
all_source_lower = ' '.join(source_files).lower()
if 'middleware' in all_source_lower: patterns.append('middleware-chain')
if 'repository' in all_source_lower: patterns.append('repository-pattern')
if 'factory' in all_source_lower: patterns.append('factory-pattern')
if 'service' in all_source_lower: patterns.append('service-layer')
if 'controller' in all_source_lower: patterns.append('controller-pattern')
index['patterns_detected'] = patterns

# CI detection
gh_workflows = glob.glob(f'{project_dir}/.github/workflows/*.yml') + glob.glob(f'{project_dir}/.github/workflows/*.yaml')
if gh_workflows:
    index['ci'] = {'has_ci': True, 'provider': 'github-actions', 'workflows': [os.path.basename(w) for w in gh_workflows]}

# API surface
routes_count = middleware_count = models_count = 0
for sf in source_files[:MAX_SCAN_FILES]:
    content = _safe_read(f'{project_dir}/{sf}')
    if not content: continue
    routes_count += len(re.findall(r'\.(get|post|put|patch|delete|all)\s*\(', content, re.I))
    middleware_count += len(re.findall(r'\.use\s*\(', content))
    models_count += len(re.findall(r'model\s+\w+\s*\{', content))
index['api_surface'] = {'routes_count': routes_count, 'middleware_count': middleware_count, 'models_count': models_count}

# Save
os.makedirs(project_vault, exist_ok=True)
with open(f'{project_vault}/project-index.json', 'w') as f:
    json.dump(index, f, indent=2)
fc = index['structure'].get('file_count', {}).get('total', 0)
dc = len(index['domains'])
print(f'project-index.json saved: {fc} files, {total_loc} LOC, {dc} domains')
print(json.dumps({'slug': project_slug, 'stack': index['stack'], 'loc': total_loc, 'file_count': fc, 'domain_count': dc, 'domains': [d["name"] for d in index["domains"]], 'patterns': index["patterns_detected"]}, indent=2))
PYINLINE
)"
```

**IMPORTANTE**: Antes de executar, peça confirmação ao usuário. O script modifica arquivos no vault (`~/.canuto/vault/`).

### Fase 2 — Cross-Reference → `onboarding-report.md`

Depois do scan, execute o cross-reference:

```bash
bash cross-reference.sh --project "<slug-do-projeto>"
```

Ou, se existirem múltiplos projetos no vault, rode sem filtro:

```bash
bash cross-reference.sh
```

### Fase 3 — Apresentar Resumo

Após ambas as fases, apresente o resumo ao usuário:

```
Auto-Analysis Complete:
- Project: {slug} ({language}/{framework})
- Indexed: {file_count} files, {loc} LOC, {domain_count} domains
- Patterns: {patterns}
- Similar projects: {match_count} (best match: {best_slug} at {match}%)
- Recommended instincts: {instinct_count}
- Relevant decisions: {decision_count}
- Reports saved:
  - ~/.canuto/vault/projects/{slug}/project-index.json
  - ~/.canuto/vault/projects/{slug}/onboarding-report.md
```

Ofereça mostrar o relatório completo ou seções específicas.

### Fase 4 (Opcional) — Gerar Canvas Visual

Se o usuário pedir visualização, use a skill `json-canvas` para gerar um canvas em `~/.canuto/vault/canvas/{slug}-analysis.canvas` com:

- Nó central: nome do projeto + stack
- Nós por domínio detectado (coloridos por confidence)
- Nós por padrão arquitetural
- Edges conectando domínios a padrões
- Se houver projetos similares: nós linkados com % de match

---

## Notas

- O `project-index.json` **não requer LLM** — é análise estática pura (Python)
- O scan é rápido (~5-15 segundos por projeto)
- Re-rodar atualiza o index (idempotente)
- Projetos sem `project-index.json` são excluídos do cross-referencing
- Para indexar um novo projeto: rode `install.sh --install` ou `/auto-analysis` no diretório do projeto
