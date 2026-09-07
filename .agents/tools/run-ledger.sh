#!/usr/bin/env bash
# Persiste os rótulos fornecidos para cada marco; use somente texto não sensível.

set -euo pipefail

usage() {
  cat >&2 <<'EOF'
uso:
  run-ledger.sh start <id> <total-3..7> <estado>
  run-ledger.sh advance <id> <concluidos> <estado>
  run-ledger.sh block <id> <motivo>
  run-ledger.sh finish <id> <estado>
  run-ledger.sh status [id] [--json]
EOF
  exit 64
}

command_name="${1:-}"
[ -n "$command_name" ] || usage
shift

project_root="${CANUTO_RUN_LEDGER_ROOT:-}"
if [ -z "$project_root" ]; then
  project_root="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
fi
ledger_dir="$project_root/.agents/tmp/run-ledger"
mkdir -p "$ledger_dir"

case "$command_name" in
  start)
    [ "$#" -eq 3 ] || usage
    run_id="$1"; value="$2"; detail="$3"; json_output=0
    ;;
  advance)
    [ "$#" -eq 3 ] || usage
    run_id="$1"; value="$2"; detail="$3"; json_output=0
    ;;
  block|finish)
    [ "$#" -eq 2 ] || usage
    run_id="$1"; value=""; detail="$2"; json_output=0
    ;;
  status)
    run_id=""; value=""; detail=""; json_output=0
    while [ "$#" -gt 0 ]; do
      case "$1" in
        --json) json_output=1 ;;
        -*) usage ;;
        *) [ -z "$run_id" ] || usage; run_id="$1" ;;
      esac
      shift
    done
    ;;
  *) usage ;;
esac

if [ -n "$run_id" ]; then
  case "$run_id" in
    *[!A-Za-z0-9._-]*|""|-*|.*) echo "run-ledger: id inválido" >&2; exit 64 ;;
  esac
  [ "${#run_id}" -le 64 ] || { echo "run-ledger: id excede 64 caracteres" >&2; exit 64; }
fi

lock_dir=""
lock_owned=0
lock_owner=""
cleanup() {
  if [ "$lock_owned" -eq 1 ] && [ -n "$lock_dir" ]; then
    current_owner=""
    IFS= read -r current_owner < "$lock_dir/owner" 2>/dev/null || current_owner=""
    if [ -n "$lock_owner" ] && [ "$current_owner" = "$lock_owner" ]; then
      rm -f "$lock_dir/owner" 2>/dev/null || true
      rmdir "$lock_dir" 2>/dev/null || true
    fi
  fi
}
trap cleanup EXIT

process_token() {
  ps -o lstart= -p "$1" 2>/dev/null \
    | tr -d '\n' \
    | cksum \
    | awk '{print $1 ":" $2}'
}

lock_age_seconds() {
  python3 - "$1" <<'PYLOCK'
import os
import sys
import time

try:
    print(max(0, int(time.time() - os.stat(sys.argv[1]).st_mtime)))
except OSError:
    print(0)
PYLOCK
}

recover_stale_lock() {
  local owner_file="$lock_dir/owner"
  local owner_pid=""
  local owner_token=""
  local owner_nonce=""
  local live_token=""
  local age_seconds="0"
  local stale_dir=""

  if [ -f "$owner_file" ]; then
    IFS=' ' read -r owner_pid owner_token owner_nonce < "$owner_file" || owner_pid=""
    case "$owner_pid" in
      *[!0-9]*|"")
        age_seconds=$(lock_age_seconds "$owner_file" 2>/dev/null || printf '0')
        [ "$age_seconds" -ge 5 ] || return 1
        ;;
      *)
        if kill -0 "$owner_pid" 2>/dev/null; then
          if [ -z "$owner_token" ] || [ -z "$owner_nonce" ]; then
            return 1
          fi
          live_token=$(process_token "$owner_pid" || true)
          if [ -z "$live_token" ] || [ "$owner_token" = "$live_token" ]; then
            return 1
          fi
        fi
        ;;
    esac
  else
    age_seconds=$(lock_age_seconds "$lock_dir" 2>/dev/null || printf '0')
    [ "$age_seconds" -ge 5 ] || return 1
  fi

  stale_dir="${lock_dir}.stale.$$.$RANDOM"
  if mv "$lock_dir" "$stale_dir" 2>/dev/null; then
    rm -rf "$stale_dir"
    return 0
  fi
  return 1
}

case "$command_name" in
  start|advance|block|finish)
    lock_dir="$ledger_dir/.${run_id}.lock"
    attempt=0
    until mkdir "$lock_dir" 2>/dev/null; do
      if recover_stale_lock; then
        continue
      fi
      attempt=$((attempt + 1))
      [ "$attempt" -lt 40 ] || { echo "run-ledger: ledger ocupado: $run_id" >&2; exit 75; }
      sleep 0.05
    done
    lock_owner="$$ $(process_token "$$" || true) $(date -u +%s).$RANDOM.$RANDOM"
    owner_tmp="$lock_dir/.owner.$$.$RANDOM"
    if ! printf '%s\n' "$lock_owner" > "$owner_tmp" \
       || ! mv "$owner_tmp" "$lock_dir/owner"; then
      rm -f "$owner_tmp" 2>/dev/null || true
      rmdir "$lock_dir" 2>/dev/null || true
      echo "run-ledger: não foi possível registrar proprietário do lock: $run_id" >&2
      exit 75
    fi
    lock_owned=1
    ;;
esac

python3 - "$ledger_dir" "$command_name" "$run_id" "$value" "$detail" "$json_output" <<'PYEOF'
import datetime as dt
import json
import os
import pathlib
import sys
import tempfile

ledger_dir, command, run_id, value, detail, json_flag = sys.argv[1:]
root = pathlib.Path(ledger_dir)


def fail(message, code=64):
    print(f"run-ledger: {message}", file=sys.stderr)
    raise SystemExit(code)


def clean_text(text, label):
    if not text or not text.strip():
        fail(f"{label} vazio")
    if len(text) > 240:
        fail(f"{label} excede 240 caracteres")
    if any(ord(char) < 32 for char in text):
        fail(f"{label} contém caractere de controle")
    return text.strip()


def path_for(identifier):
    return root / f"{identifier}.json"


def load(identifier):
    path = path_for(identifier)
    try:
        with path.open(encoding="utf-8") as handle:
            data = json.load(handle)
    except FileNotFoundError:
        fail(f"execução não encontrada: {identifier}", 66)
    except (OSError, ValueError, TypeError):
        fail(f"ledger inválido: {identifier}", 65)
    return data


def save(identifier, data):
    target = path_for(identifier)
    fd, staged = tempfile.mkstemp(prefix=f".{identifier}.", suffix=".tmp", dir=root)
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as handle:
            json.dump(data, handle, ensure_ascii=True, indent=2, sort_keys=True)
            handle.write("\n")
            handle.flush()
            os.fsync(handle.fileno())
        os.replace(staged, target)
    finally:
        if os.path.exists(staged):
            os.unlink(staged)


def render(data):
    total = int(data["total"])
    done = int(data["done"])
    bar = "#" * done + "-" * (total - done)
    status = data["status"]
    if status == "active":
        tail = f"{data['state']} | continuo automaticamente"
    elif status == "blocked":
        tail = f"BLOQUEADO: {data['blocker']} | aguarda mudança da precondição"
    else:
        tail = f"CONCLUÍDO: {data['state']}"
    return f"PROGRESSO [{bar}] {done}/{total} | {tail}"


now = dt.datetime.now(dt.timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z")

if command == "start":
    try:
        total = int(value)
    except ValueError:
        fail("total deve ser inteiro")
    if total < 3 or total > 7:
        fail("total deve ficar entre 3 e 7")
    target = path_for(run_id)
    if target.exists():
        fail(f"id já existe: {run_id}", 73)
    state = clean_text(detail, "estado")
    data = {
        "schemaVersion": 1,
        "id": run_id,
        "total": total,
        "done": 0,
        "status": "active",
        "state": state,
        "createdAt": now,
        "updatedAt": now,
    }
    save(run_id, data)
    print(render(data))
elif command == "advance":
    data = load(run_id)
    try:
        done = int(value)
    except ValueError:
        fail("concluídos deve ser inteiro")
    if done <= int(data["done"]):
        fail("avanço deve ser monotônico")
    if done >= int(data["total"]):
        fail("use finish para concluir o último marco")
    data.update(done=done, status="active", state=clean_text(detail, "estado"), updatedAt=now)
    data.pop("blocker", None)
    save(run_id, data)
    print(render(data))
elif command == "block":
    data = load(run_id)
    if data["status"] == "complete":
        fail("execução concluída não pode ser bloqueada")
    data.update(status="blocked", blocker=clean_text(detail, "motivo"), updatedAt=now)
    save(run_id, data)
    print(render(data))
elif command == "finish":
    data = load(run_id)
    data.update(done=int(data["total"]), status="complete", state=clean_text(detail, "estado"), updatedAt=now)
    data.pop("blocker", None)
    save(run_id, data)
    print(render(data))
elif command == "status":
    if run_id:
        records = load(run_id)
    else:
        records = []
        for path in sorted(root.glob("*.json")):
            try:
                with path.open(encoding="utf-8") as handle:
                    records.append(json.load(handle))
            except (OSError, ValueError, TypeError):
                continue
        records.sort(key=lambda item: item.get("updatedAt", ""), reverse=True)
    if json_flag == "1":
        print(json.dumps(records, ensure_ascii=True, sort_keys=True))
    elif isinstance(records, list):
        for record in records:
            print(render(record))
    else:
        print(render(records))
PYEOF

if [ "$command_name" != "status" ]; then
  event_log="$project_root/.agents/tools/event-log.sh"
  if [ -f "$event_log" ]; then
    bash "$event_log" append RUN_PROGRESS "id=$run_id" "action=$command_name" >/dev/null 2>&1 || true
  fi
fi
