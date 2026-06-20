#!/usr/bin/env bash
# update-agentos.sh — Update agentOS harness in an embedded project.
#
# Usage:
#   # Auto-fetch from git remote (reads source URL from .trae/VERSION):
#   bash scripts/update-agentos.sh --version 0.4.0
#   bash scripts/update-agentos.sh --version latest
#
#   # Manual: use a local copy of new agentOS:
#   bash scripts/update-agentos.sh --local /path/to/new-agentos
#
#   # Preview without changes:
#   bash scripts/update-agentos.sh --version 0.4.0 --dry-run
#   bash scripts/update-agentos.sh --local /path/to/new-agentos --dry-run
#
# Safety: fails safe (preserves project content) on any uncertainty.
# Rollback: git reset --hard pre-agentos-<old-version>
set -euo pipefail

PROJECT_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
VERSION_FILE="$PROJECT_ROOT/.trae/VERSION"
MANIFEST="$PROJECT_ROOT/.trae/MANIFEST"
CONFLICT_LOG="$PROJECT_ROOT/.trae/update-conflicts.log"
TMP_DIR="/tmp/agentos-update-$$"

# ── Parse arguments ──
MODE=""
TARGET=""
DRY_RUN=false

while [ $# -gt 0 ]; do
  case "$1" in
    --version) MODE="remote"; TARGET="${2:?--version requires a value}"; shift 2;;
    --local)   MODE="local";  TARGET="${2:?--local requires a path}";   shift 2;;
    --dry-run) DRY_RUN=true; shift;;
    *) echo "Unknown arg: $1" >&2; exit 1;;
  esac
done

if [ -z "$MODE" ]; then
  echo "Usage: bash scripts/update-agentos.sh --version <tag> [--dry-run]"
  echo "       bash scripts/update-agentos.sh --local <path> [--dry-run]"
  exit 1
fi

# ── 1. Read current version ──
INSTALLED=$(awk -F': ' '/^version/{print $2}' "$VERSION_FILE" | tr -d ' ')
SOURCE_URL=$(awk -F': ' '/^source/{print $2}' "$VERSION_FILE" | tr -d ' ')

echo "=== agentOS Update ==="
echo "Project:     $PROJECT_ROOT"
echo "Installed:   $INSTALLED"
echo ""

# ── 2. Obtain new agentOS source ──
if [ "$MODE" = "remote" ]; then
  if [ "$SOURCE_URL" = "local" ] || [ -z "$SOURCE_URL" ]; then
    echo "ERROR: .trae/VERSION has source: local — no remote URL to fetch from." >&2
    echo "Set 'source: <git-url>' in .trae/VERSION, or use --local <path>." >&2
    exit 1
  fi

  echo "Fetching from: $SOURCE_URL"
  echo "Version:       $TARGET"
  echo ""

  # Clone to temp dir
  git clone --depth 50 "$SOURCE_URL" "$TMP_DIR" 2>&1 | sed 's/^/  /'

  if [ "$TARGET" != "latest" ]; then
    git -C "$TMP_DIR" checkout "$TARGET" 2>&1 | sed 's/^/  /' || {
      echo "ERROR: tag/branch '$TARGET' not found in $SOURCE_URL" >&2
      rm -rf "$TMP_DIR"
      exit 1
    }
  fi

  NEW_SRC="$TMP_DIR"
elif [ "$MODE" = "local" ]; then
  NEW_SRC="$TARGET"
  if [ ! -f "$NEW_SRC/.trae/VERSION" ]; then
    echo "ERROR: $NEW_SRC/.trae/VERSION not found — not a valid agentOS source." >&2
    exit 1
  fi
fi

LATEST=$(awk -F': ' '/^version/{print $2}' "$NEW_SRC/.trae/VERSION" | tr -d ' ')
echo "Available:   $LATEST"

if [ "$INSTALLED" = "$LATEST" ] && [ "$TARGET" != "latest" ]; then
  echo "Already up to date."
  rm -rf "$TMP_DIR"
  exit 0
fi
echo ""

# ── 3. Dry-run preview ──
if [ "$DRY_RUN" = true ]; then
  echo "=== Dry Run Preview ==="
  echo ""
  echo "Framework files (overwrite):"
  while IFS= read -r line; do
    case "$line" in ''|\#*) continue;; esac
    path=$(echo "$line" | awk '{print $1}')
    kind=$(echo "$line" | awk '{print $2}')
    [ "$kind" = "framework" ] && echo "  $path"
  done < "$MANIFEST"
  echo ""
  echo "Shared files (merge by section markers):"
  while IFS= read -r line; do
    case "$line" in ''|\#*) continue;; esac
    path=$(echo "$line" | awk '{print $1}')
    kind=$(echo "$line" | awk '{print $2}')
    [ "$kind" = "shared" ] && echo "  $path"
  done < "$MANIFEST"
  echo ""
  echo "Project files (preserved): docs/*, .trae/specs/<id>/*, .trae/memory/project_memory.md, scripts/*.sh"
  echo ""
  echo "Run without --dry-run to execute."
  rm -rf "$TMP_DIR"
  exit 0
fi

# ── 4. Pre-flight: clean working tree ──
if [ -n "$(git -C "$PROJECT_ROOT" status --short 2>/dev/null || true)" ]; then
  echo "ERROR: Working tree not clean. Commit or stash first." >&2
  rm -rf "$TMP_DIR"
  exit 1
fi

# ── 5. Create rollback point ──
BRANCH="agentos-update-${LATEST}"
git -C "$PROJECT_ROOT" checkout -b "$BRANCH"
TAG="pre-agentos-${INSTALLED}"
git -C "$PROJECT_ROOT" tag "$TAG"
echo "Rollback: git reset --hard $TAG"
echo ""

# ── 6. Execute update ──
: > "$CONFLICT_LOG"
FRAMEWORK_COUNT=0
SHARED_COUNT=0

while IFS= read -r line; do
  case "$line" in ''|\#*) continue;; esac
  path=$(echo "$line" | awk '{print $1}')
  kind=$(echo "$line" | awk '{print $2}')
  dest="$PROJECT_ROOT/$path"
  src="$NEW_SRC/$path"

  if [ ! -f "$src" ]; then
    echo "SKIP (not in source): $path"
    continue
  fi

  case "$kind" in
    framework)
      mkdir -p "$(dirname "$dest")"
      cp "$src" "$dest"
      FRAMEWORK_COUNT=$((FRAMEWORK_COUNT + 1))
      ;;
    shared)
      # Merge: preserve <!-- agentOS:project begin/end --> sections
      python3 - "$dest" "$src" <<'PYEOF'
import sys, re
dest_path, src_path = sys.argv[1], sys.argv[2]
with open(dest_path) as f: dest = f.read()
with open(src_path) as f: src = f.read()

project_sections = re.findall(
    r'<!-- agentOS:project begin -->(.*?)<!-- agentOS:project end -->',
    dest, re.DOTALL)

new_sections = re.findall(
    r'<!-- agentOS:project begin -->(.*?)<!-- agentOS:project end -->',
    src, re.DOTALL)

if len(project_sections) != len(new_sections):
    print(f"WARN: section count mismatch in {dest_path} "
          f"(current={len(project_sections)}, new={len(new_sections)}); "
          f"keeping current file", file=sys.stderr)
    sys.exit(0)

result = src
for old, new in zip(project_sections, new_sections):
    result = result.replace(
        f'<!-- agentOS:project begin -->{new}<!-- agentOS:project end -->',
        f'<!-- agentOS:project begin -->{old}<!-- agentOS:project end -->')

with open(dest_path, 'w') as f: f.write(result)
PYEOF
      SHARED_COUNT=$((SHARED_COUNT + 1))
      ;;
  esac
done < "$MANIFEST"

# Check for conflicts: new files that exist in project but not in manifest
while IFS= read -r src_file; do
  rel="${src_file#$NEW_SRC/}"
  if grep -qx "$rel framework" "$MANIFEST" 2>/dev/null || \
     grep -qx "$rel shared" "$MANIFEST" 2>/dev/null; then
    continue
  fi
  dest_file="$PROJECT_ROOT/$rel"
  if [ -e "$dest_file" ]; then
    echo "CONFLICT: $rel exists in project but not in manifest" | tee -a "$CONFLICT_LOG"
  fi
done < <(find "$NEW_SRC" -name '*.md' -o -name '*.sh' -o -name '*.json' | sort)

echo ""
echo "Updated: $FRAMEWORK_COUNT framework files, $SHARED_COUNT shared files."
[ -s "$CONFLICT_LOG" ] && echo "Conflicts: $(wc -l < "$CONFLICT_LOG") (see $CONFLICT_LOG)"

# ── 7. Update version stamp ──
cp "$NEW_SRC/.trae/VERSION" "$VERSION_FILE"
echo "Version: $INSTALLED → $LATEST"
echo ""

# ── 8. Verify ──
echo "=== Smoke Test ==="
if bash "$PROJECT_ROOT/eval/run-smoke.sh"; then
  echo ""
  echo "=== Update Complete ==="
  echo "Branch:   $BRANCH"
  echo "Rollback: git reset --hard $TAG"
  echo ""
  echo "Next: review changes, run project tests, then merge $BRANCH."
else
  echo "Smoke tests FAILED. Rollback: git reset --hard $TAG" >&2
  rm -rf "$TMP_DIR"
  exit 1
fi

rm -rf "$TMP_DIR"
