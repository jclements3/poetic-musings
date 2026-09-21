#!/usr/bin/env bash
# pipeline.sh -- run the full gate locally, same order as CI.
# Usage: ./pipeline.sh [REPO_ROOT]     Exit: first failing stage's code
set -u
ROOT="${1:-.}"
HERE="$(cd "$(dirname "$0")" && pwd)"
OUT="$ROOT/.scan-out"; mkdir -p "$OUT"
rc=0

echo "--- stage 1: secrets"
python3 "$HERE/secrets.py" "$ROOT" || rc=1

echo "--- stage 2: dependency pins"
if [ -f "$ROOT/requirements.txt" ]; then
  python3 "$HERE/deps.py" "$ROOT/requirements.txt" || rc=1
else
  echo "no requirements.txt; skipping"
fi

echo "--- stage 3: SAST triage (bandit -> SARIF -> summary)"
if command -v bandit > /dev/null && [ -d "$ROOT/app" ]; then
  bandit -r "$ROOT/app" -f sarif -o "$OUT/bandit.sarif" --exit-zero -q
fi
if [ -f "$OUT/bandit.sarif" ]; then
  python3 "$HERE/triage.py" "$OUT/bandit.sarif" > "$OUT/bandit.summary.json"
else
  echo "no SARIF input; skipping"
fi

echo "--- stage 4: policy gate"
if [ -f "$OUT/bandit.summary.json" ]; then
  python3 "$HERE/gate.py" "$HERE/policy.json" "$OUT"/*.summary.json || rc=1
fi

exit $rc
