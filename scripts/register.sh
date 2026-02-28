#!/usr/bin/env bash
set -euo pipefail

# ERC-8004 Agent Registration — Multi-Chain
# Usage:
#   CHAIN=base ./scripts/register.sh <agent-uri>
#   CHAIN=ethereum ./scripts/register.sh <agent-uri>
#   CHAIN=avalanche-fuji ./scripts/register.sh <agent-uri>
#   CHAIN=base-sepolia ./scripts/register.sh ipfs

CHAIN="${CHAIN:-base}"

# Chain configuration
declare -A CHAIN_CONFIG
# Mainnets
CHAIN_CONFIG[ethereum]="1|https://eth.llamarpc.com|0x8004A169FB4a3325136EB29fA0ceB6D2e539a432|https://etherscan.io"
CHAIN_CONFIG[base]="8453|https://mainnet.base.org|0x8004A169FB4a3325136EB29fA0ceB6D2e539a432|https://basescan.org"
CHAIN_CONFIG[arbitrum]="42161|https://arb1.arbitrum.io/rpc|0x8004A169FB4a3325136EB29fA0ceB6D2e539a432|https://arbiscan.io"
CHAIN_CONFIG[optimism]="10|https://mainnet.optimism.io|0x8004A169FB4a3325136EB29fA0ceB6D2e539a432|https://optimistic.etherscan.io"
CHAIN_CONFIG[polygon]="137|https://polygon-rpc.com|0x8004A169FB4a3325136EB29fA0ceB6D2e539a432|https://polygonscan.com"
CHAIN_CONFIG[avalanche]="43114|https://api.avax.network/ext/bc/C/rpc|0x8004A169FB4a3325136EB29fA0ceB6D2e539a432|https://snowtrace.io"
CHAIN_CONFIG[bnb]="56|https://bsc-dataseed.binance.org|0x8004A169FB4a3325136EB29fA0ceB6D2e539a432|https://bscscan.com"
CHAIN_CONFIG[gnosis]="100|https://rpc.gnosischain.com|0x8004A169FB4a3325136EB29fA0ceB6D2e539a432|https://gnosisscan.io"
CHAIN_CONFIG[celo]="42220|https://forno.celo.org|0x8004A169FB4a3325136EB29fA0ceB6D2e539a432|https://celoscan.io"
# Testnets
CHAIN_CONFIG[sepolia]="11155111|https://rpc.sepolia.org|0x8004A818BFB912233c491871b3d84c89A494BD9e|https://sepolia.etherscan.io"
CHAIN_CONFIG[base-sepolia]="84532|https://sepolia.base.org|0x8004A818BFB912233c491871b3d84c89A494BD9e|https://sepolia.basescan.org"
CHAIN_CONFIG[arbitrum-sepolia]="421614|https://sepolia-rollup.arbitrum.io/rpc|0x8004A818BFB912233c491871b3d84c89A494BD9e|https://sepolia.arbiscan.io"
CHAIN_CONFIG[avalanche-fuji]="43113|https://api.avax-test.network/ext/bc/C/rpc|0x8004A818BFB912233c491871b3d84c89A494BD9e|https://testnet.snowtrace.io"
CHAIN_CONFIG[optimism-sepolia]="11155420|https://sepolia.optimism.io|0x8004A818BFB912233c491871b3d84c89A494BD9e|https://sepolia-optimism.etherscan.io"

if [ -z "${CHAIN_CONFIG[$CHAIN]+x}" ]; then
  echo "Error: Unknown chain '$CHAIN'"
  echo ""
  echo "Supported chains:"
  echo "  Mainnets: ethereum, base, arbitrum, optimism, polygon, avalanche, bnb, gnosis, celo"
  echo "  Testnets: sepolia, base-sepolia, arbitrum-sepolia, avalanche-fuji, optimism-sepolia"
  exit 1
fi

IFS='|' read -r CHAIN_ID RPC_URL IDENTITY_REGISTRY EXPLORER <<< "${CHAIN_CONFIG[$CHAIN]}"
RPC_URL="${RPC_URL_OVERRIDE:-$RPC_URL}"

if [ -z "${PRIVATE_KEY:-}" ]; then
  echo "Error: PRIVATE_KEY environment variable is required"
  exit 1
fi

AGENT_URI="${1:-}"

if [ -z "$AGENT_URI" ]; then
  echo "Usage: CHAIN=<chain> ./scripts/register.sh <agent-uri|ipfs>"
  echo ""
  echo "Examples:"
  echo "  # Direct URL (agent serves its own registration.json)"
  echo "  CHAIN=base ./scripts/register.sh https://myagent.xyz/registration.json"
  echo ""
  echo "  # IPFS mode (upload metadata to Pinata, then register)"
  echo "  CHAIN=base-sepolia PINATA_JWT=xxx AGENT_URL=https://myagent.up.railway.app \\"
  echo "    AGENT_NAME='My Agent' AGENT_DESCRIPTION='What it does' \\"
  echo "    ./scripts/register.sh ipfs"
  exit 1
fi

# If "ipfs" mode, create and upload registration file first
if [ "$AGENT_URI" = "ipfs" ]; then
  if [ -z "${PINATA_JWT:-}" ]; then
    echo "Error: PINATA_JWT is required for IPFS upload"
    echo ""
    echo "Get a free JWT at https://app.pinata.cloud/developers/api-keys"
    exit 1
  fi

  AGENT_NAME="${AGENT_NAME:-My ERC-8004 Agent}"
  AGENT_DESCRIPTION="${AGENT_DESCRIPTION:-An AI agent with on-chain identity}"
  AGENT_IMAGE="${AGENT_IMAGE:-}"
  AGENT_URL="${AGENT_URL:-}"

  if [ -z "$AGENT_URL" ]; then
    echo "Error: AGENT_URL is required for IPFS mode"
    echo ""
    echo "Set AGENT_URL to your deployed agent's base URL:"
    echo "  AGENT_URL=https://my-agent.up.railway.app PINATA_JWT=xxx ./scripts/register.sh ipfs"
    echo ""
    echo "Deploy your agent first (Railway, Docker, etc.), then register with IPFS."
    exit 1
  fi

  # Remove trailing slash
  AGENT_URL="${AGENT_URL%/}"

  REGISTRATION_JSON=$(cat <<EOF
{
  "type": "https://eips.ethereum.org/EIPS/eip-8004#registration-v1",
  "name": "$AGENT_NAME",
  "description": "$AGENT_DESCRIPTION",
  "image": "${AGENT_IMAGE:-${AGENT_URL}/public/agent.png}",
  "services": [
    { "name": "web", "endpoint": "${AGENT_URL}/" },
    { "name": "A2A", "endpoint": "${AGENT_URL}/.well-known/agent-card.json", "version": "0.3.0" },
    { "name": "MCP", "endpoint": "${AGENT_URL}/mcp", "version": "2025-11-25" },
    { "name": "OASF", "endpoint": "${AGENT_URL}/oasf", "version": "v0.8.0", "skills": ["tool_interaction/api_schema_understanding", "tool_interaction/workflow_automation"], "domains": ["technology/software_engineering"] },
    { "name": "heartbeat", "endpoint": "${AGENT_URL}/heartbeat" }
  ],
  "x402Support": false,
  "active": true,
  "registrations": [
    {
      "agentId": "REPLACE_WITH_YOUR_AGENT_ID_AFTER_REGISTRATION",
      "agentRegistry": "eip155:${CHAIN_ID}:${IDENTITY_REGISTRY}"
    }
  ],
  "supportedTrust": ["reputation"],
  "capabilities": [
    "natural_language_processing/information_retrieval_synthesis",
    "tool_interaction/api_schema_understanding"
  ]
}
EOF
)

  echo "Uploading registration to IPFS via Pinata..."
  echo ""

  TMPFILE=$(mktemp /tmp/agent-registration-XXXXXX.json)
  echo "$REGISTRATION_JSON" > "$TMPFILE"

  HTTP_CODE=$(curl -s -o /tmp/pinata-response.json -w "%{http_code}" \
    -X POST "https://api.pinata.cloud/pinning/pinFileToIPFS" \
    -H "Authorization: Bearer $PINATA_JWT" \
    -F "file=@$TMPFILE" \
    -F "pinataMetadata={\"name\": \"agent-registration-${CHAIN}-${CHAIN_ID}.json\"}")

  rm -f "$TMPFILE"

  if [ "$HTTP_CODE" != "200" ]; then
    echo "Error: Pinata API returned HTTP $HTTP_CODE"
    echo "Response: $(cat /tmp/pinata-response.json 2>/dev/null)"
    echo ""
    echo "Check your PINATA_JWT is valid: https://app.pinata.cloud/developers/api-keys"
    rm -f /tmp/pinata-response.json
    exit 1
  fi

  RESPONSE=$(cat /tmp/pinata-response.json)
  rm -f /tmp/pinata-response.json

  IPFS_HASH=$(echo "$RESPONSE" | grep -o '"IpfsHash":"[^"]*"' | cut -d'"' -f4)

  if [ -z "$IPFS_HASH" ]; then
    echo "Error: Failed to extract IPFS hash from response"
    echo "Response: $RESPONSE"
    exit 1
  fi

  AGENT_URI="ipfs://$IPFS_HASH"
  echo "Uploaded to IPFS: $AGENT_URI"
  echo "Gateway:  https://gateway.pinata.cloud/ipfs/$IPFS_HASH"
fi

echo ""
echo "=== ERC-8004 Agent Registration ==="
echo "Chain:     $CHAIN (Chain ID: $CHAIN_ID)"
echo "Registry:  $IDENTITY_REGISTRY"
echo "Agent URI: $AGENT_URI"
echo ""

if ! command -v cast &> /dev/null; then
  echo "Error: 'cast' (Foundry) is required. Install it with:"
  echo "  curl -L https://foundry.paradigm.xyz | bash && foundryup"
  exit 1
fi

echo "Registering agent..."

TX_HASH=$(cast send "$IDENTITY_REGISTRY" \
  "register(string)(uint256)" "$AGENT_URI" \
  --rpc-url "$RPC_URL" \
  --private-key "$PRIVATE_KEY" \
  --json | grep -o '"transactionHash":"[^"]*"' | cut -d'"' -f4)

echo "Transaction sent: $TX_HASH"
echo "Explorer: $EXPLORER/tx/$TX_HASH"

echo "Waiting for confirmation..."
sleep 5

RECEIPT=$(cast receipt "$TX_HASH" --rpc-url "$RPC_URL" --json 2>/dev/null || echo "")

if [ -n "$RECEIPT" ]; then
  # Extract agentId from Transfer event (topic[3] = tokenId = agentId)
  AGENT_ID=""
  if command -v python3 &> /dev/null; then
    AGENT_ID=$(echo "$RECEIPT" | python3 -c "
import sys, json
r = json.load(sys.stdin)
for log in r.get('logs', []):
    topics = log.get('topics', [])
    if len(topics) >= 4 and topics[0].startswith('0xddf252'):
        print(int(topics[3], 16))
        break
" 2>/dev/null)
  fi

  echo ""
  echo "=== Registration Successful! ==="
  echo ""
  if [ -n "$AGENT_ID" ]; then
    echo "  Agent ID:  $AGENT_ID"
    echo "  Registry:  eip155:${CHAIN_ID}:${IDENTITY_REGISTRY}"
    echo "  Explorer:  $EXPLORER/tx/$TX_HASH"
    echo ""
    echo "=== Next Steps ==="
    echo ""
    echo "  1. Update registration.json:"
    echo "     Replace \"REPLACE_WITH_YOUR_AGENT_ID_AFTER_REGISTRATION\" with $AGENT_ID"
    echo ""
    echo "  2. Update the agentRegistry to your chain:"
    echo "     \"agentRegistry\": \"eip155:${CHAIN_ID}:${IDENTITY_REGISTRY}\""
    echo ""
    echo "  3. Redeploy your agent"
    echo ""
    echo "  4. Verify:"
    echo "     CHAIN=$CHAIN ./scripts/verify-agent.sh $AGENT_ID"
  else
    echo "  Transaction: $EXPLORER/tx/$TX_HASH"
    echo "  Registry:    eip155:${CHAIN_ID}:${IDENTITY_REGISTRY}"
    echo ""
    echo "  Could not auto-detect agentId. Find it on the explorer:"
    echo "  $EXPLORER/tx/$TX_HASH (look for Transfer event tokenId)"
    echo ""
    echo "  Then update registration.json and redeploy."
  fi
else
  echo ""
  echo "Transaction submitted. Check status at:"
  echo "$EXPLORER/tx/$TX_HASH"
fi
