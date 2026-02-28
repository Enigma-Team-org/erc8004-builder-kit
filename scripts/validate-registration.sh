#!/usr/bin/env bash
set -euo pipefail

# ERC-8004 Registration Validator
# Checks registration.json for common mistakes before deploying.
# Usage: ./scripts/validate-registration.sh [path/to/registration.json]

FILE="${1:-registration.json}"
ERRORS=0
WARNINGS=0

if [ ! -f "$FILE" ]; then
  echo "Error: File not found: $FILE"
  echo "Usage: ./scripts/validate-registration.sh [path/to/registration.json]"
  exit 1
fi

echo "=== ERC-8004 Registration Validator ==="
echo "File: $FILE"
echo ""

# Check valid JSON
if ! python3 -c "import json; json.load(open('$FILE'))" 2>/dev/null; then
  echo "FAIL: Invalid JSON"
  exit 1
fi

check_field() {
  local field="$1"
  local value
  value=$(python3 -c "import json; d=json.load(open('$FILE')); print(d.get('$field', ''))" 2>/dev/null)
  if [ -z "$value" ]; then
    echo "  FAIL  Missing required field: $field"
    ERRORS=$((ERRORS + 1))
  fi
}

check_placeholder() {
  local pattern="$1"
  local label="$2"
  if grep -qi "$pattern" "$FILE"; then
    echo "  FAIL  Placeholder found: $label (search for '$pattern')"
    ERRORS=$((ERRORS + 1))
  fi
}

echo "--- Required Fields ---"
for field in type name description services active; do
  check_field "$field"
done
echo ""

echo "--- Placeholders ---"
check_placeholder "YOUR-DOMAIN" "YOUR-DOMAIN (replace with your actual domain)"
check_placeholder "YOUR_DOMAIN" "YOUR_DOMAIN (replace with your actual domain)"
check_placeholder "REPLACE_WITH" "REPLACE_WITH placeholder"
check_placeholder "localhost" "localhost (use your production URL)"
check_placeholder "example.com" "example.com (use your actual domain)"
check_placeholder "My Agent" "Generic name 'My Agent' (give it a real name)"
check_placeholder "My Python Agent" "Generic name 'My Python Agent' (give it a real name)"
echo ""

echo "--- Services ---"
SERVICES_COUNT=$(python3 -c "
import json
d = json.load(open('$FILE'))
services = d.get('services', [])
print(len(services))
" 2>/dev/null)

if [ "$SERVICES_COUNT" = "0" ]; then
  echo "  FAIL  services array is empty (add at least: web, A2A, MCP, heartbeat)"
  ERRORS=$((ERRORS + 1))
else
  echo "  OK    $SERVICES_COUNT services found"
fi

# Check A2A endpoint
python3 -c "
import json, sys
d = json.load(open('$FILE'))
for s in d.get('services', []):
    if s.get('name') == 'A2A':
        ep = s.get('endpoint', '')
        if '/.well-known/agent-card.json' not in ep:
            print('  FAIL  A2A endpoint must point to /.well-known/agent-card.json (got: ' + ep + ')')
            sys.exit(1)
        else:
            print('  OK    A2A endpoint correct')
        break
else:
    print('  WARN  No A2A service found')
" 2>/dev/null || ERRORS=$((ERRORS + 1))

# Check MCP version
python3 -c "
import json, sys
d = json.load(open('$FILE'))
for s in d.get('services', []):
    if s.get('name') == 'MCP':
        v = s.get('version', '')
        if v != '2025-11-25':
            print('  WARN  MCP version should be 2025-11-25 (got: ' + v + ')')
        else:
            print('  OK    MCP version correct')
        break
" 2>/dev/null

# Check for non-verifiable services
python3 -c "
import json
d = json.load(open('$FILE'))
bad = ['x402-signals', 'telegram-bot']
for s in d.get('services', []):
    name = s.get('name', '')
    if name in bad:
        print(f'  FAIL  Non-verifiable service \"{name}\" will cause Service=0 on scanner')
        print(f'        Move to capabilities array or description instead')
" 2>/dev/null
echo ""

echo "--- OASF Taxonomy ---"
python3 -c "
import json
d = json.load(open('$FILE'))
for s in d.get('services', []):
    if s.get('name') == 'OASF':
        for skill in s.get('skills', []):
            parts = skill.split('/')
            if len(parts) > 2:
                print(f'  FAIL  OASF skill has 3+ levels: {skill} (max 2: category/skill)')
            elif len(parts) < 2:
                print(f'  WARN  OASF skill has only 1 level: {skill} (expected: category/skill)')
            else:
                print(f'  OK    {skill}')
        for domain in s.get('domains', []):
            parts = domain.split('/')
            if len(parts) > 2:
                print(f'  FAIL  OASF domain has 3+ levels: {domain} (max 2: category/domain)')
            else:
                print(f'  OK    {domain}')
        break
" 2>/dev/null
echo ""

echo "--- CAIP-10 Format ---"
python3 -c "
import json, re
d = json.load(open('$FILE'))
for reg in d.get('registrations', []):
    ar = reg.get('agentRegistry', '')
    if re.match(r'^eip155:\d+:0x[a-fA-F0-9]{40}$', ar):
        print(f'  OK    {ar}')
    elif ar:
        print(f'  FAIL  Not CAIP-10 format: {ar}')
        print(f'        Expected: eip155:{{chainId}}:0x{{address}}')
" 2>/dev/null
echo ""

echo "--- Registration Type ---"
python3 -c "
import json
d = json.load(open('$FILE'))
t = d.get('type', '')
expected = 'https://eips.ethereum.org/EIPS/eip-8004#registration-v1'
if t == expected:
    print('  OK    type field correct')
elif not t:
    print('  FAIL  Missing type field')
else:
    print(f'  WARN  Unexpected type: {t}')
" 2>/dev/null
echo ""

echo "================================="
if [ "$ERRORS" -gt 0 ]; then
  echo "RESULT: FAIL ($ERRORS errors found)"
  echo ""
  echo "Fix the errors above before deploying."
  exit 1
else
  echo "RESULT: PASS"
  echo ""
  echo "Your registration.json looks good! Deploy and register."
fi
