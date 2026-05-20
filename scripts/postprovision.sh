#!/usr/bin/env bash
# postprovision hook: install deps and run the AI Search index setup script.
# azd exposes deployment outputs as environment variables in this process.

set -euo pipefail

echo "=== postprovision: indexing data/*.docx into AI Search ==="

if [[ -z "${AI_SEARCH_ENDPOINT:-}" || -z "${AI_FOUNDRY_ENDPOINT:-}" ]]; then
  echo "Skipping: AI_SEARCH_ENDPOINT or AI_FOUNDRY_ENDPOINT not set in azd env."
  exit 0
fi

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

python -m pip install --quiet --upgrade pip
python -m pip install --quiet -r scripts/requirements.txt
python scripts/setup_aisearch_index.py
