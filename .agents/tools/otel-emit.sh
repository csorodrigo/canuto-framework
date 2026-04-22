#!/usr/bin/env bash
# Shared OTLP/JSON emitter for Claude Code tool hook observability.

set -o pipefail

otel_endpoint() {
  local endpoint="${CANUTO_TOOLS_OTLP_ENDPOINT:-${OTEL_EXPORTER_OTLP_ENDPOINT:-http://localhost:4318}}"
  while [ "${endpoint%/}" != "$endpoint" ]; do
    endpoint="${endpoint%/}"
  done
  case "$endpoint" in
    http://localhost:4317|http://127.0.0.1:4317) endpoint="${endpoint%4317}4318" ;;
  esac
  printf '%s\n' "$endpoint"
}

otel_enabled() {
  [ "${CANUTO_TOOLS_OTLP_ENABLED:-}" = "1" ] && return 0
  [ "${CLAUDE_CODE_ENABLE_TELEMETRY:-}" = "1" ]
}

_json_escape_strings() {
  if command -v python3 >/dev/null 2>&1; then
    python3 -c 'import json,sys; print("\n".join(json.dumps(v) for v in sys.argv[1:]))' "$@"
  elif command -v jq >/dev/null 2>&1; then
    local value
    for value in "$@"; do
      printf '%s' "$value" | jq -Rs .
    done
  else
    local value
    for value in "$@"; do
      printf '""\n'
    done
  fi
}

_json_escape_string() {
  local value="${1:-}"
  local escaped
  escaped=$(_json_escape_strings "$value" | sed -n '1p')
  printf '%s' "${escaped:-\"\"}"
}

otel_attr_int() {
  local value="${2:-0}"
  case "$value" in ''|*[!0-9]*) value=0 ;; esac
  printf '{"key":%s,"value":{"intValue":"%s"}}' \
    "$(_json_escape_string "$1")" "$value"
}

otel_random_hex() {
  local bytes="$1"
  od -An -vN"$bytes" -tx1 /dev/urandom 2>/dev/null | tr -d ' \n'
}

otel_now_unix_nano() {
  local raw=""
  if command -v gdate >/dev/null 2>&1; then
    raw=$(gdate +%s%N 2>/dev/null || true)
  else
    raw=$(date +%s%N 2>/dev/null || true)
  fi
  case "$raw" in
    ''|*[!0-9]*) ;;
    *) [ "${#raw}" -ge 19 ] && { printf '%s\n' "$raw"; return 0; } ;;
  esac
  local seconds random nano
  seconds=$(date +%s 2>/dev/null || printf '0')
  random=$(od -An -N4 -tu4 /dev/urandom 2>/dev/null | tr -d ' ')
  case "$random" in ''|*[!0-9]*) random=0 ;; esac
  nano=$((random % 1000000000))
  printf '%s%09d\n' "$seconds" "$nano"
}

otel_hook_source() {
  local source="${CANUTO_OTEL_HOOK_SOURCE:-${OTEL_HOOK_SOURCE:-}}"
  [ -n "$source" ] || source="$(basename "$0" .sh 2>/dev/null || printf 'unknown')"
  printf '%s\n' "$source"
}

otel_resource_attributes() {
  if [ -n "${CANUTO_OTEL_RESOURCE_ATTRIBUTES_CACHE:-}" ]; then
    printf '%s' "$CANUTO_OTEL_RESOURCE_ATTRIBUTES_CACHE"
    return 0
  fi
  local host host_json
  host=$(hostname -s 2>/dev/null || hostname 2>/dev/null || printf 'unknown')
  host_json=$(_json_escape_string "$host")
  CANUTO_OTEL_RESOURCE_ATTRIBUTES_CACHE=$(printf '%s,%s,%s,%s' \
    '{"key":"service.name","value":{"stringValue":"claude-code-tools"}}' \
    '{"key":"service.namespace","value":{"stringValue":"canuto"}}' \
    '{"key":"deployment.environment","value":{"stringValue":"local-dev"}}' \
    '{"key":"host.name","value":{"stringValue":'"${host_json:-\"\"}"'}}')
  printf '%s' "$CANUTO_OTEL_RESOURCE_ATTRIBUTES_CACHE"
}

otel_extra_attributes() {
  local attrs=""
  if [ -n "${CANUTO_OTEL_RETRY_COUNT:-}" ]; then
    attrs="${attrs},$(otel_attr_int "tool.retry_count" "$CANUTO_OTEL_RETRY_COUNT")"
  fi
  if [ -n "${CANUTO_OTEL_PENDING_COUNT:-}" ]; then
    attrs="${attrs},$(otel_attr_int "tool.pending_count" "$CANUTO_OTEL_PENDING_COUNT")"
  fi
  if [ -n "${CANUTO_OTEL_EXTRA_ATTRIBUTES:-}" ]; then
    if _otel_extra_attrs_is_valid "$CANUTO_OTEL_EXTRA_ATTRIBUTES"; then
      attrs="${attrs},${CANUTO_OTEL_EXTRA_ATTRIBUTES}"
    fi
  fi
  printf '%s' "$attrs"
}

_otel_extra_attrs_is_valid() {
  local candidate="$1"
  if command -v python3 >/dev/null 2>&1; then
    python3 -c 'import json,sys; json.loads("[" + sys.argv[1] + "]")' "$candidate" >/dev/null 2>&1
  elif command -v jq >/dev/null 2>&1; then
    printf '[%s]' "$candidate" | jq -e . >/dev/null 2>&1
  else
    return 1
  fi
}

otel_post_json() {
  local path="$1"
  local payload="$2"
  local endpoint
  endpoint="$(otel_endpoint)"
  [ "${CANUTO_OTEL_PRINT_PAYLOAD:-}" = "1" ] && printf '%s\n' "$payload" >&2
  local err_sink=/dev/null
  [ "${CANUTO_OTEL_DEBUG:-}" = "1" ] && err_sink=/tmp/canuto-otel-emit.err
  (
    curl --silent --show-error \
      --max-time 1 --connect-timeout 1 \
      --output /dev/null \
      -H 'Content-Type: application/json' \
      -d "$payload" \
      "${endpoint}${path}" \
      2>>"$err_sink" || true
  ) </dev/null >/dev/null 2>&1 &
  disown 2>/dev/null || true
  return 0
}

otel_emit_span() {
  otel_enabled || return 0
  local tool_name="${1:-unknown}"
  local outcome="${2:-success}"
  local duration_ms="${3:-0}"
  local file_path="${4:-}"
  local command_truncated="${5:-}"
  (
    case "$duration_ms" in ''|*[!0-9]*) duration_ms=0 ;; esac
    command_truncated="${command_truncated:0:200}"
    local end_ns start_ns status_code status_message trace_id span_id attrs payload
    local hook_source span_name escaped_values
    local tool_name_json outcome_json hook_source_json file_path_json command_json span_name_json status_message_json
    end_ns=$(otel_now_unix_nano)
    start_ns=$((end_ns - (duration_ms * 1000000)))
    [ "$start_ns" -lt 0 ] 2>/dev/null && start_ns="$end_ns"
    trace_id=$(otel_random_hex 16)
    span_id=$(otel_random_hex 8)
    case "$outcome" in
      success|allowed|flagged|cleared)
        status_code=1
        status_message=""
        ;;
      blocked)
        status_code=2
        status_message="blocked by hook"
        ;;
      *)
        status_code=2
        status_message="$outcome"
        ;;
    esac

    hook_source=$(otel_hook_source)
    span_name="tool.$tool_name"
    escaped_values=$(_json_escape_strings "$tool_name" "$outcome" "$hook_source" "$file_path" "$command_truncated" "$span_name" "$status_message")
    {
      IFS= read -r tool_name_json
      IFS= read -r outcome_json
      IFS= read -r hook_source_json
      IFS= read -r file_path_json
      IFS= read -r command_json
      IFS= read -r span_name_json
      IFS= read -r status_message_json
    } <<EOF
$escaped_values
EOF

    attrs='{"key":"tool.name","value":{"stringValue":'"${tool_name_json:-\"\"}"'}},{"key":"tool.outcome","value":{"stringValue":'"${outcome_json:-\"\"}"'}},{"key":"tool.duration_ms","value":{"intValue":"'"$duration_ms"'"}},{"key":"tool.hook_source","value":{"stringValue":'"${hook_source_json:-\"\"}"'}}'
    [ -n "$file_path" ] && attrs="${attrs}"',{"key":"tool.file_path","value":{"stringValue":'"${file_path_json:-\"\"}"'}}'
    [ -n "$command_truncated" ] && attrs="${attrs}"',{"key":"tool.command","value":{"stringValue":'"${command_json:-\"\"}"'}}'
    attrs="${attrs}$(otel_extra_attributes)"

    payload=$(printf '{"resourceSpans":[{"resource":{"attributes":[%s]},"scopeSpans":[{"scope":{"name":"canuto"},"spans":[{"traceId":"%s","spanId":"%s","name":%s,"kind":"SPAN_KIND_INTERNAL","startTimeUnixNano":"%s","endTimeUnixNano":"%s","attributes":[%s],"status":{"code":%s,"message":%s}}]}]}]}' \
      "$(otel_resource_attributes)" "$trace_id" "$span_id" "${span_name_json:-\"tool.unknown\"}" \
      "$start_ns" "$end_ns" "$attrs" "$status_code" "${status_message_json:-\"\"}")
    otel_post_json "/v1/traces" "$payload"
  ) </dev/null >/dev/null 2>&1 &
  disown 2>/dev/null || true
  return 0
}

otel_emit_counter() {
  otel_enabled || return 0
  local tool_name="${1:-unknown}"
  local outcome="${2:-success}"
  (
    local time_ns attrs payload escaped_values tool_name_json outcome_json hook_source hook_source_json
    time_ns=$(otel_now_unix_nano)
    hook_source=$(otel_hook_source)
    escaped_values=$(_json_escape_strings "$tool_name" "$outcome" "$hook_source")
    {
      IFS= read -r tool_name_json
      IFS= read -r outcome_json
      IFS= read -r hook_source_json
    } <<EOF
$escaped_values
EOF
    attrs='{"key":"tool.name","value":{"stringValue":'"${tool_name_json:-\"\"}"'}},{"key":"tool.outcome","value":{"stringValue":'"${outcome_json:-\"\"}"'}},{"key":"tool.hook_source","value":{"stringValue":'"${hook_source_json:-\"\"}"'}}'
    payload=$(printf '{"resourceMetrics":[{"resource":{"attributes":[%s]},"scopeMetrics":[{"scope":{"name":"canuto"},"metrics":[{"name":"claude_code_tools.tool_call.count","unit":"1","sum":{"aggregationTemporality":"AGGREGATION_TEMPORALITY_DELTA","isMonotonic":true,"dataPoints":[{"attributes":[%s],"timeUnixNano":"%s","asInt":"1"}]}}]}]}]}' \
      "$(otel_resource_attributes)" "$attrs" "$time_ns")
    otel_post_json "/v1/metrics" "$payload"
  ) </dev/null >/dev/null 2>&1 &
  disown 2>/dev/null || true
  return 0
}

if [ "${1:-}" = "--self-test" ]; then
  export CANUTO_TOOLS_OTLP_ENABLED=1
  export CANUTO_OTEL_PRINT_PAYLOAD=1
  export CANUTO_OTEL_HOOK_SOURCE="otel-emit-self-test"
  otel_emit_span "test.tool" "success" 42 "/tmp/foo" "echo hi"
  otel_emit_counter "test.tool" "success"
  echo "self-test emitted" >&2
  exit 0
fi

if [ "${BASH_SOURCE[0]}" = "$0" ]; then
  command="${1:-}"
  shift || true
  case "$command" in
    span) otel_emit_span "$@" ;;
    counter) otel_emit_counter "$@" ;;
    "") ;;
    *) printf 'usage: %s [--self-test|span|counter]\n' "$0" >&2; exit 2 ;;
  esac
fi
