#!/usr/bin/env pwsh
# postprovision hook: install deps and run the AI Search index setup script.
# azd exposes deployment outputs as environment variables in this process.

$ErrorActionPreference = 'Stop'

Write-Host "=== postprovision: indexing data/*.docx into AI Search ===" -ForegroundColor Cyan

if (-not $env:AI_SEARCH_ENDPOINT -or -not $env:AI_FOUNDRY_ENDPOINT) {
    Write-Host "Skipping: AI_SEARCH_ENDPOINT or AI_FOUNDRY_ENDPOINT not set in azd env." -ForegroundColor Yellow
    exit 0
}

$repoRoot = Split-Path -Parent $PSScriptRoot
Push-Location $repoRoot
try {
    python -m pip install --quiet --upgrade pip
    python -m pip install --quiet -r scripts/requirements.txt
    python scripts/setup_aisearch_index.py
}
finally {
    Pop-Location
}
