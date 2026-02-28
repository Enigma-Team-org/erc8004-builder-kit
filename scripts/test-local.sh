#!/usr/bin/env bash
set -euo pipefail

# ERC-8004 Local Agent Tester
# Runs endpoint tests against your local agent before deploying.
# Usage: ./scripts/test-local.sh [base-url]

BASE_URL="${1:-http://localhost:3000}"
PASS=0
FAIL=0
TOTAL=0

test_endpoint() {
  local method="$1"
  local path="$2"
  local label="$3"
  local check="$4"
  local body="${5:-}"
  TOTAL=$((TOTAL + 1))

  local response status_code
  if [ "$method" = "GET" ]; then
    response=$(curl -s -w "\n%{http_code}" "$BASE_URL$path" 2>/dev/null) || true
  else
    response=$(curl -s -w "\n%{http_code}" -X POST "$BASE_URL$path" \
      -H "Content-Type: application/json" \
      -d "$body" 2>/dev/null) || true
  fi

  status_code=$(echo "$response" | tail -1)
  local body_content
  body_content=$(echo "$response" | sed '$d')

  case "$check" in
    "status_200")
      if [ "$status_code" = "200" ]; then
        echo "  PASS  $label (HTTP $status_code)"
        PASS=$((PASS + 1))
      else
        echo "  FAIL  $label (HTTP $status_code, expected 200)"
        FAIL=$((FAIL + 1))
      fi
      ;;
    "has_json")
      if [ "$status_code" = "200" ] && echo "$body_content" | python3 -c "import json,sys; json.load(sys.stdin)" 2>/dev/null; then
        echo "  PASS  $label (valid JSON)"
        PASS=$((PASS + 1))
      else
        echo "  FAIL  $label (HTTP $status_code or invalid JSON)"
        FAIL=$((FAIL + 1))
      fi
      ;;
    "has_services")
      if echo "$body_content" | python3 -c "
import json, sys
d = json.load(sys.stdin)
s = d.get('services', [])
if len(s) >= 1:
    print(f'{len(s)} services: ' + ', '.join(x.get('name','?') for x in s))
    sys.exit(0)
sys.exit(1)
" 2>/dev/null; then
        echo "  PASS  $label"
        PASS=$((PASS + 1))
      else
        echo "  FAIL  $label (no services array or empty)"
        FAIL=$((FAIL + 1))
      fi
      ;;
    "jsonrpc_result")
      if echo "$body_content" | python3 -c "
import json, sys
d = json.load(sys.stdin)
if 'result' in d:
    r = d['result']
    v = r.get('protocolVersion', r.get('serverInfo', {}).get('name', ''))
    print(f'protocolVersion: {v}' if v else 'result found')
    sys.exit(0)
sys.exit(1)
" 2>/dev/null; then
        echo "  PASS  $label"
        PASS=$((PASS + 1))
      else
        echo "  FAIL  $label (no 'result' in response)"
        FAIL=$((FAIL + 1))
      fi
      ;;
    "jsonrpc_tools")
      if echo "$body_content" | python3 -c "
import json, sys
d = json.load(sys.stdin)
tools = d.get('result', {}).get('tools', [])
print(f'{len(tools)} tools')
sys.exit(0 if len(tools) >= 1 else 1)
" 2>/dev/null; then
        echo "  PASS  $label"
        PASS=$((PASS + 1))
      else
        echo "  FAIL  $label (no tools returned)"
        FAIL=$((FAIL + 1))
      fi
      ;;
    "parse_error")
      if echo "$body_content" | python3 -c "
import json, sys
d = json.load(sys.stdin)
code = d.get('error', {}).get('code', 0)
if code == -32700:
    sys.exit(0)
sys.exit(1)
" 2>/dev/null; then
        echo "  PASS  $label (code: -32700)"
        PASS=$((PASS + 1))
      else
        echo "  FAIL  $label (expected error code -32700, got HTTP $status_code)"
        echo "        If you get 500, add try/catch around req.json() and return -32700"
        FAIL=$((FAIL + 1))
      fi
      ;;
  esac
}

echo "=== ERC-8004 Local Agent Tests ==="
echo "Target: $BASE_URL"
echo ""

# Check if server is running
if ! curl -s "$BASE_URL" > /dev/null 2>&1; then
  echo "ERROR: Cannot reach $BASE_URL"
  echo ""
  echo "Start your agent first:"
  echo "  npm run dev          (TypeScript/Hono)"
  echo "  python server.py     (Python/FastAPI)"
  exit 1
fi

echo "--- Core Endpoints ---"
test_endpoint "GET"  "/heartbeat"        "Heartbeat"               "status_200"
test_endpoint "GET"  "/registration.json" "Registration JSON"       "has_services"
test_endpoint "GET"  "/.well-known/agent-card.json"  "Agent Card"  "has_json"
echo ""

echo "--- MCP Protocol ---"
test_endpoint "POST" "/mcp" "MCP initialize" "jsonrpc_result" \
  '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-11-25","capabilities":{},"clientInfo":{"name":"test","version":"1.0"}}}'

test_endpoint "POST" "/mcp" "MCP tools/list" "jsonrpc_tools" \
  '{"jsonrpc":"2.0","id":2,"method":"tools/list","params":{}}'
echo ""

echo "--- A2A Protocol ---"
test_endpoint "POST" "/a2a" "A2A empty body (-32700)" "parse_error" ""
echo ""

echo "--- Optional ---"
test_endpoint "GET"  "/oasf" "OASF endpoint" "has_json"
echo ""

echo "================================="
echo "Result: $PASS/$TOTAL passed"
if [ "$FAIL" -gt 0 ]; then
  echo ""
  echo "$FAIL test(s) failed. Fix them before deploying."
  exit 1
else
  echo ""
  echo "All tests passed! Ready to deploy."
fi
