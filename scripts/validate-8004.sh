#!/bin/bash
# ─────────────────────────────────────────────────────────────
# 8004scan Metadata Validator
# Validates an ERC-8004 agent's metadata and endpoints locally.
# Usage: ./validate-8004.sh <BASE_URL>
# Example: ./validate-8004.sh https://apex-arbitrage-agent-production.up.railway.app
# ─────────────────────────────────────────────────────────────

set -euo pipefail

BASE_URL="${1:?Usage: $0 <BASE_URL>}"
BASE_URL="${BASE_URL%/}"  # Remove trailing slash

PASS=0
FAIL=0
WARN=0

pass() { echo "  [PASS] $1"; ((PASS++)); }
fail() { echo "  [FAIL] $1"; ((FAIL++)); }
warn() { echo "  [WARN] $1"; ((WARN++)); }

echo "========================================"
echo "  8004scan Metadata Validator"
echo "  Target: $BASE_URL"
echo "  Date:   $(date -u +%Y-%m-%dT%H:%M:%SZ)"
echo "========================================"
echo ""

# ── 1. Health Check ──────────────────────────────────────────
echo "1. Health Check"
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" --max-time 10 "$BASE_URL/api/health" 2>/dev/null || echo "000")
if [ "$HTTP_CODE" = "200" ]; then
  pass "Health endpoint returns 200"
else
  fail "Health endpoint returned $HTTP_CODE (expected 200)"
fi
echo ""

# ── 2. Fetch Registration JSON ──────────────────────────────
echo "2. Registration JSON"
REG=$(curl -s --max-time 10 "$BASE_URL/registration.json" 2>/dev/null || echo "")
if [ -z "$REG" ]; then
  fail "Could not fetch registration.json"
  echo ""
  echo "Cannot continue without registration.json. Aborting."
  exit 1
fi

# Validate JSON
if ! echo "$REG" | python3 -c "import sys,json; json.load(sys.stdin)" 2>/dev/null; then
  fail "registration.json is not valid JSON"
  exit 1
fi
pass "registration.json is valid JSON"

# ── 3. Required Fields (WA001-WA005) ────────────────────────
echo ""
echo "3. Required Fields"

# WA001/WA002: type
TYPE=$(echo "$REG" | python3 -c "import sys,json; print(json.load(sys.stdin).get('type',''))" 2>/dev/null)
EXPECTED_TYPE="https://eips.ethereum.org/EIPS/eip-8004#registration-v1"
if [ "$TYPE" = "$EXPECTED_TYPE" ]; then
  pass "WA001/WA002: type field is correct"
else
  if [ -z "$TYPE" ]; then
    fail "WA001: Missing type field"
  else
    fail "WA002: Invalid type value: $TYPE"
  fi
fi

# WA003: name
NAME=$(echo "$REG" | python3 -c "import sys,json; print(json.load(sys.stdin).get('name',''))" 2>/dev/null)
NAME_LEN=${#NAME}
if [ "$NAME_LEN" -ge 3 ] && [ "$NAME_LEN" -le 50 ]; then
  pass "WA003: name is valid ($NAME_LEN chars): $NAME"
elif [ "$NAME_LEN" -eq 0 ]; then
  fail "WA003: Missing name field"
else
  fail "WA003: name length $NAME_LEN not in range 3-50"
fi

# WA004: description
DESC_LEN=$(echo "$REG" | python3 -c "import sys,json; print(len(json.load(sys.stdin).get('description','')))" 2>/dev/null)
if [ "$DESC_LEN" -ge 50 ]; then
  pass "WA004: description is present ($DESC_LEN chars)"
elif [ "$DESC_LEN" -gt 0 ]; then
  warn "WA004: description is short ($DESC_LEN chars, recommend 50+)"
else
  fail "WA004: Missing description field"
fi

# WA005: image
IMAGE_URL=$(echo "$REG" | python3 -c "import sys,json; print(json.load(sys.stdin).get('image',''))" 2>/dev/null)
if [ -n "$IMAGE_URL" ]; then
  if echo "$IMAGE_URL" | grep -q "^https://"; then
    IMG_CODE=$(curl -s -o /dev/null -w "%{http_code}" --max-time 10 "$IMAGE_URL" 2>/dev/null || echo "000")
    if [ "$IMG_CODE" = "200" ]; then
      pass "WA005: image URL is valid and accessible"
    else
      fail "WA005: image URL returned HTTP $IMG_CODE"
    fi
  else
    fail "WA005: image URL missing https:// scheme: $IMAGE_URL"
  fi
else
  warn "IA001: Missing image field"
fi

# ── 4. Boolean Fields (WA015, WA016) ────────────────────────
echo ""
echo "4. Boolean Fields"

ACTIVE_TYPE=$(echo "$REG" | python3 -c "
import sys,json
d=json.load(sys.stdin)
v=d.get('active')
if v is True or v is False: print('bool')
elif v is None: print('missing')
else: print('invalid')
" 2>/dev/null)
case "$ACTIVE_TYPE" in
  bool) pass "WA015: active is boolean" ;;
  missing) warn "WA015: active field not set (recommend true)" ;;
  *) fail "WA015: active is not boolean" ;;
esac

X402_TYPE=$(echo "$REG" | python3 -c "
import sys,json
d=json.load(sys.stdin)
v=d.get('x402Support')
if v is True or v is False: print('bool')
elif v is None: print('missing')
else: print('invalid')
" 2>/dev/null)
case "$X402_TYPE" in
  bool) pass "WA016: x402Support is boolean" ;;
  missing) warn "WA016: x402Support field not set" ;;
  *) fail "WA016: x402Support is not boolean" ;;
esac

# ── 5. Services Array (WA006-WA009, WA020, WA031) ───────────
echo ""
echo "5. Services Array"

HAS_SERVICES=$(echo "$REG" | python3 -c "
import sys,json
d=json.load(sys.stdin)
if 'services' in d and isinstance(d['services'], list): print('ok')
elif 'endpoints' in d: print('legacy')
elif 'endpoint' in d: print('singular')
else: print('missing')
" 2>/dev/null)

case "$HAS_SERVICES" in
  ok) pass "Services array present" ;;
  legacy) fail "WA031: Using legacy 'endpoints' field — rename to 'services'" ;;
  singular) fail "WA020: Found singular 'endpoint' — use 'services' array" ;;
  missing) fail "IA002: No services defined" ;;
esac

if [ "$HAS_SERVICES" = "ok" ]; then
  SVC_COUNT=$(echo "$REG" | python3 -c "import sys,json; print(len(json.load(sys.stdin).get('services',[])))" 2>/dev/null)
  if [ "$SVC_COUNT" -eq 0 ]; then
    fail "IA003: services array is empty"
  else
    pass "Services array has $SVC_COUNT entries"
  fi

  # Validate each service
  echo "$REG" | python3 -c "
import sys,json
d=json.load(sys.stdin)
for i,s in enumerate(d.get('services',[])):
    if not isinstance(s, dict):
        print(f'FAIL WA007: services[{i}] is not an object')
        continue
    if 'endpoint' not in s:
        print(f'FAIL WA008: services[{i}] missing endpoint field')
        continue
    if not s['endpoint']:
        print(f'FAIL WA009: services[{i}] has empty endpoint')
        continue
    name = s.get('name','?')
    ep = s['endpoint']
    if not ep.startswith('https://'):
        print(f'WARN services[{i}] ({name}): endpoint is not HTTPS')
    else:
        print(f'OK services[{i}] ({name}): {ep}')
    ver = s.get('version')
    if name == 'MCP' and not ver:
        print(f'WARN IA020: MCP service missing version (use YYYY-MM-DD)')
    if name == 'A2A' and not ver:
        print(f'WARN IA022: A2A service missing version')
" 2>/dev/null | while read -r line; do
    case "$line" in
      FAIL*) fail "${line#FAIL }" ;;
      WARN*) warn "${line#WARN }" ;;
      OK*)   pass "${line#OK }" ;;
    esac
  done
fi

# ── 6. Registrations (WA010-WA013, WA021) ───────────────────
echo ""
echo "6. Registrations"

HAS_REGS=$(echo "$REG" | python3 -c "
import sys,json
d=json.load(sys.stdin)
if 'registrations' in d and isinstance(d['registrations'], list): print('ok')
elif 'registration' in d: print('singular')
else: print('missing')
" 2>/dev/null)

case "$HAS_REGS" in
  ok) pass "Registrations array present" ;;
  singular) fail "WA021: Found singular 'registration' — use 'registrations' array" ;;
  missing) warn "IA004: Missing registrations array" ;;
esac

if [ "$HAS_REGS" = "ok" ]; then
  echo "$REG" | python3 -c "
import sys,json,re
d=json.load(sys.stdin)
regs=d.get('registrations',[])
if not regs:
    print('WARN IA005: registrations array is empty')
for i,r in enumerate(regs):
    if not isinstance(r, dict):
        print(f'FAIL WA011: registrations[{i}] is not an object')
        continue
    ar = r.get('agentRegistry','')
    if not ar:
        print(f'FAIL WA012: registrations[{i}] missing agentRegistry')
    elif not re.match(r'^eip155:\d+:0x[a-fA-F0-9]{40}$', ar):
        print(f'FAIL WA013: registrations[{i}] agentRegistry not CAIP-10: {ar}')
    else:
        print(f'OK registrations[{i}]: agentId={r.get(\"agentId\",\"?\")} registry={ar}')
    aid = r.get('agentId')
    if aid is None:
        print(f'WARN IA006/IA007: registrations[{i}] missing or null agentId')
" 2>/dev/null | while read -r line; do
    case "$line" in
      FAIL*) fail "${line#FAIL }" ;;
      WARN*) warn "${line#WARN }" ;;
      OK*)   pass "${line#OK }" ;;
    esac
  done
fi

# ── 7. Trust and Wallet (WA014, WA030, WA083) ───────────────
echo ""
echo "7. Trust and Wallet"

echo "$REG" | python3 -c "
import sys,json,re
d=json.load(sys.stdin)

# WA014
st = d.get('supportedTrust')
if st is not None:
    if isinstance(st, list):
        if len(st) > 0:
            print('OK supportedTrust: ' + ', '.join(st))
        else:
            print('WARN IA008: supportedTrust array is empty')
    else:
        print('FAIL WA014: supportedTrust is not an array')
else:
    print('WARN IA008: supportedTrust not defined')

# WA030
aw = d.get('agentWallet','')
if aw:
    print('FAIL WA083: agentWallet found in off-chain JSON — remove it, set only via setAgentWallet()')
    if not re.match(r'^eip155:\d+:0x[a-fA-F0-9]{40}$', aw):
        print('FAIL WA030: agentWallet not in CAIP-10 format')
" 2>/dev/null | while read -r line; do
    case "$line" in
      FAIL*) fail "${line#FAIL }" ;;
      WARN*) warn "${line#WARN }" ;;
      OK*)   pass "${line#OK }" ;;
    esac
  done

# ── 8. MCP Endpoint Probes ──────────────────────────────────
echo ""
echo "8. MCP Endpoint"

MCP_URL=$(echo "$REG" | python3 -c "
import sys,json
d=json.load(sys.stdin)
for s in d.get('services',[]):
    if s.get('name') == 'MCP':
        print(s.get('endpoint',''))
        break
" 2>/dev/null)

if [ -n "$MCP_URL" ]; then
  # Initialize
  INIT_RESP=$(curl -s -X POST "$MCP_URL" --max-time 10 \
    -H "Content-Type: application/json" \
    -d '{"jsonrpc":"2.0","method":"initialize","id":1,"params":{"protocolVersion":"2025-03-26","capabilities":{},"clientInfo":{"name":"validator","version":"1.0.0"}}}' 2>/dev/null || echo "")
  if echo "$INIT_RESP" | python3 -c "import sys,json; d=json.load(sys.stdin); assert d['result']['protocolVersion']" 2>/dev/null; then
    pass "MCP initialize returns protocolVersion"
  else
    fail "MCP initialize did not return protocolVersion"
  fi

  # Tools list
  TOOLS_RESP=$(curl -s -X POST "$MCP_URL" --max-time 10 \
    -H "Content-Type: application/json" \
    -d '{"jsonrpc":"2.0","method":"tools/list","id":2}' 2>/dev/null || echo "")
  TOOL_COUNT=$(echo "$TOOLS_RESP" | python3 -c "import sys,json; print(len(json.load(sys.stdin).get('result',{}).get('tools',[])))" 2>/dev/null || echo "0")
  if [ "$TOOL_COUNT" -gt 0 ]; then
    pass "MCP tools/list returns $TOOL_COUNT tools"
  else
    fail "MCP tools/list returned 0 tools"
  fi
else
  warn "No MCP service endpoint found — skipping MCP probes"
fi

# ── 9. A2A Endpoint Probes ──────────────────────────────────
echo ""
echo "9. A2A Endpoint"

A2A_URL=$(echo "$REG" | python3 -c "
import sys,json
d=json.load(sys.stdin)
for s in d.get('services',[]):
    if s.get('name') == 'A2A':
        print(s.get('endpoint',''))
        break
" 2>/dev/null)

if [ -n "$A2A_URL" ]; then
  # Extract base URL for .well-known
  A2A_BASE=$(echo "$A2A_URL" | python3 -c "import sys; from urllib.parse import urlparse; u=urlparse(sys.stdin.read().strip()); print(f'{u.scheme}://{u.netloc}')" 2>/dev/null)

  AGENT_CARD=$(curl -s --max-time 10 "$A2A_BASE/.well-known/agent.json" 2>/dev/null || echo "")
  if echo "$AGENT_CARD" | python3 -c "import sys,json; d=json.load(sys.stdin); assert d.get('name')" 2>/dev/null; then
    pass "A2A .well-known/agent.json is valid"
  else
    fail "IA024: A2A .well-known/agent.json not found or invalid"
  fi
else
  warn "No A2A service endpoint found — skipping A2A probes"
fi

# ── Summary ──────────────────────────────────────────────────
echo ""
echo "========================================"
echo "  Results: $PASS passed, $FAIL failed, $WARN warnings"
echo "========================================"

if [ "$FAIL" -gt 0 ]; then
  echo ""
  echo "  Fix all FAIL items before deploying."
  echo "  FAIL items map to WA0XX codes that reduce your Compliance score."
  exit 1
else
  echo ""
  echo "  All critical checks passed."
  if [ "$WARN" -gt 0 ]; then
    echo "  Address WARN items to maximize your Publisher and Compliance scores."
  fi
  exit 0
fi
