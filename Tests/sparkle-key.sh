#!/bin/bash
# Checks the Sparkle key format and derivation against a public test vector.
set -euo pipefail
cd "$(dirname "$0")/.."

# RFC 8032 test key. Never use this seed to sign releases.
test_seed="nWGxne/9WmC6hEr0kuwsxERJxWl7MmkZcDusAxyuf2A="
public_key="$(printf '%s' "$test_seed" | swift Scripts/sparkle-public-key.swift)"
[[ "$public_key" == "11qYAYKxCrfVS/7TyWQHOg7hcvPapiMlrwIaaPcHURo=" ]]
if printf '%s' 'invalid-key' | swift Scripts/sparkle-public-key.swift >/dev/null 2>&1; then
    echo "Invalid Sparkle key was accepted." >&2
    exit 1
fi
echo "PASS: Sparkle public key matches the seed; malformed keys are rejected"
