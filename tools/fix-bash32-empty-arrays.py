#!/usr/bin/env python3
from pathlib import Path

path = Path("install.sh")
text = path.read_text(encoding="utf-8")

old_builder = r'''build_refresh_args() {
  local skip_next=0
  local arg=""
  REFRESH_ARGS=()
  for arg in "${ORIGINAL_ARGS[@]}"; do
    if [ "$skip_next" -eq 1 ]; then
      skip_next=0
      continue
    fi
    case "$arg" in
      --channel|--version|--ref|--rollback) skip_next=1 ;;
      *) REFRESH_ARGS+=("$arg") ;;
    esac
  done
  if [ "$ROLLBACK_REQUESTED" = true ]; then
    local has_update=false
    for arg in "${REFRESH_ARGS[@]}"; do [ "$arg" = "--update" ] && has_update=true; done
    [ "$has_update" = true ] || REFRESH_ARGS=(--update "${REFRESH_ARGS[@]}")
  fi
}
'''
new_builder = r'''build_refresh_args() {
  local skip_next=0
  local arg=""
  REFRESH_ARGS=()

  # Bash 3.2 + `set -u` treats expansion of a declared-but-empty array as an
  # unbound variable. Guard the expansion explicitly; this path is exercised
  # when the installer is invoked without arguments by repair-dispatch tests.
  if [ "${#ORIGINAL_ARGS[@]}" -gt 0 ]; then
    for arg in "${ORIGINAL_ARGS[@]}"; do
      if [ "$skip_next" -eq 1 ]; then
        skip_next=0
        continue
      fi
      case "$arg" in
        --channel|--version|--ref|--rollback) skip_next=1 ;;
        *) REFRESH_ARGS+=("$arg") ;;
      esac
    done
  fi

  if [ "$ROLLBACK_REQUESTED" = true ]; then
    local has_update=false
    if [ "${#REFRESH_ARGS[@]}" -gt 0 ]; then
      for arg in "${REFRESH_ARGS[@]}"; do
        [ "$arg" = "--update" ] && has_update=true
      done
    fi
    if [ "$has_update" != true ]; then
      if [ "${#REFRESH_ARGS[@]}" -gt 0 ]; then
        REFRESH_ARGS=(--update "${REFRESH_ARGS[@]}")
      else
        REFRESH_ARGS=(--update)
      fi
    fi
  fi
}
'''
if text.count(old_builder) != 1:
    raise SystemExit(f"build_refresh_args block expected once, found {text.count(old_builder)}")
text = text.replace(old_builder, new_builder, 1)

old_refresh = r'''    CANUTO_BOOTSTRAPPED=1 \
      CANUTO_REPO_URL="$REPO_URL" \
      CANUTO_SOURCE_KIND="$SOURCE_KIND" \
      CANUTO_SOURCE_REF="$SOURCE_REF" \
      CANUTO_SOURCE_CHANNEL="$SOURCE_CHANNEL" \
      CANUTO_SOURCE_VERSION="$SOURCE_VERSION" \
      CANUTO_SOURCE_TRANSPORT="$SOURCE_TRANSPORT" \
      CANUTO_ROLLBACK_REQUESTED="$ROLLBACK_REQUESTED" \
      bash "$remote_installer" "${REFRESH_ARGS[@]}"
    exit $?
'''
new_refresh = r'''    if [ "${#REFRESH_ARGS[@]}" -gt 0 ]; then
      CANUTO_BOOTSTRAPPED=1 \
        CANUTO_REPO_URL="$REPO_URL" \
        CANUTO_SOURCE_KIND="$SOURCE_KIND" \
        CANUTO_SOURCE_REF="$SOURCE_REF" \
        CANUTO_SOURCE_CHANNEL="$SOURCE_CHANNEL" \
        CANUTO_SOURCE_VERSION="$SOURCE_VERSION" \
        CANUTO_SOURCE_TRANSPORT="$SOURCE_TRANSPORT" \
        CANUTO_ROLLBACK_REQUESTED="$ROLLBACK_REQUESTED" \
        bash "$remote_installer" "${REFRESH_ARGS[@]}"
    else
      CANUTO_BOOTSTRAPPED=1 \
        CANUTO_REPO_URL="$REPO_URL" \
        CANUTO_SOURCE_KIND="$SOURCE_KIND" \
        CANUTO_SOURCE_REF="$SOURCE_REF" \
        CANUTO_SOURCE_CHANNEL="$SOURCE_CHANNEL" \
        CANUTO_SOURCE_VERSION="$SOURCE_VERSION" \
        CANUTO_SOURCE_TRANSPORT="$SOURCE_TRANSPORT" \
        CANUTO_ROLLBACK_REQUESTED="$ROLLBACK_REQUESTED" \
        bash "$remote_installer"
    fi
    exit $?
'''
if text.count(old_refresh) != 1:
    raise SystemExit(f"remote refresh block expected once, found {text.count(old_refresh)}")
text = text.replace(old_refresh, new_refresh, 1)

old_library_return = r'''if [ "${CANUTO_INSTALL_LIBRARY_ONLY:-0}" = "1" ]; then
  set -- "${ORIGINAL_ARGS[@]}"
  return 0 2>/dev/null || exit 0
fi
'''
new_library_return = r'''if [ "${CANUTO_INSTALL_LIBRARY_ONLY:-0}" = "1" ]; then
  if [ "${#ORIGINAL_ARGS[@]}" -gt 0 ]; then
    set -- "${ORIGINAL_ARGS[@]}"
  else
    set --
  fi
  return 0 2>/dev/null || exit 0
fi
'''
if text.count(old_library_return) != 1:
    raise SystemExit(f"library return block expected once, found {text.count(old_library_return)}")
text = text.replace(old_library_return, new_library_return, 1)

path.write_text(text, encoding="utf-8")

tests_path = Path("test-framework.sh")
tests = tests_path.read_text(encoding="utf-8")

old_source_fixture = r'''  (cd "$SOURCE_EMPTY" && env HOME="$SOURCE_HOME" "${SOURCE_ENV[@]}" /bin/bash "$FRAMEWORK_DIR/install.sh" "${SOURCE_ARGS[@]}" >/dev/null 2>&1) || SOURCE_RC=$?
'''
new_source_fixture = r'''  # Bash 3.2 + `set -u` rejects expansion of SOURCE_ENV when the
  # environment list is intentionally empty. Keep the exact same parser cases,
  # but call env without an empty-array expansion in that branch.
  if [ "${#SOURCE_ENV[@]}" -gt 0 ]; then
    (cd "$SOURCE_EMPTY" && env HOME="$SOURCE_HOME" "${SOURCE_ENV[@]}" /bin/bash "$FRAMEWORK_DIR/install.sh" "${SOURCE_ARGS[@]}" >/dev/null 2>&1) || SOURCE_RC=$?
  else
    (cd "$SOURCE_EMPTY" && env HOME="$SOURCE_HOME" /bin/bash "$FRAMEWORK_DIR/install.sh" "${SOURCE_ARGS[@]}" >/dev/null 2>&1) || SOURCE_RC=$?
  fi
'''
if tests.count(old_source_fixture) != 1:
    raise SystemExit(
        "SOURCE_ENV fixture invocation expected once, "
        f"found {tests.count(old_source_fixture)}"
    )
tests = tests.replace(old_source_fixture, new_source_fixture, 1)
tests_path.write_text(tests, encoding="utf-8")

print(
    "Bash 3.2 empty-array expansions are guarded in installer refresh, "
    "library paths, and source-parser fixtures"
)
