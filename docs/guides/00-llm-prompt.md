# AI-Assisted Agent Creation

Copy everything below the line and paste it into Claude, ChatGPT, or any LLM. Then tell it what kind of agent you want to build.

---

## Prompt: Build Me an ERC-8004 Agent

You are helping me build an ERC-8004 AI agent. Follow these rules exactly.

### What is ERC-8004?
ERC-8004 is the standard for trustless AI agent services on EVM chains. Agents get an NFT identity (agentId), serve metadata at a URL (agentURI), and are discoverable on scanners like erc-8004scan.xyz and 8004scan.io.

### Required Endpoints
My agent MUST serve these endpoints:

| Method | Path | Response |
|--------|------|----------|
| GET | `/` | HTML dashboard |
| GET | `/heartbeat` | `{"status":"alive","timestamp":"..."}` |
| GET | `/registration.json` | Full ERC-8004 metadata (see schema below) |
| GET | `/.well-known/agent-card.json` | Same as registration.json (A2A discovery) |
| GET | `/.well-known/agent-registration.json` | Same as registration.json |
| POST | `/mcp` | JSON-RPC 2.0 (MCP protocol v2025-11-25) |
| POST | `/a2a` | JSON-RPC 2.0 (A2A protocol v0.3.0) |
| GET | `/oasf` | OASF skills and domains |

### registration.json Schema
```json
{
  "type": "https://eips.ethereum.org/EIPS/eip-8004#registration-v1",
  "name": "AGENT_NAME",
  "description": "What it does (50-500 chars)",
  "image": "https://YOUR-DOMAIN/public/agent.png",
  "services": [
    { "name": "web", "endpoint": "https://YOUR-DOMAIN/" },
    { "name": "A2A", "endpoint": "https://YOUR-DOMAIN/.well-known/agent-card.json", "version": "0.3.0" },
    { "name": "MCP", "endpoint": "https://YOUR-DOMAIN/mcp", "version": "2025-11-25", "mcpTools": ["tool1", "tool2"] },
    { "name": "OASF", "endpoint": "https://YOUR-DOMAIN/oasf", "version": "v0.8.0", "skills": [], "domains": [] },
    { "name": "heartbeat", "endpoint": "https://YOUR-DOMAIN/heartbeat" }
  ],
  "x402Support": false,
  "active": true,
  "registrations": [
    {
      "agentId": "REPLACE_WITH_YOUR_AGENT_ID_AFTER_REGISTRATION",
      "agentRegistry": "eip155:84532:0x8004A818BFB912233c491871b3d84c89A494BD9e"
    }
  ],
  "supportedTrust": ["reputation"],
  "capabilities": ["natural_language_processing/information_retrieval_synthesis"]
}
```

### MCP Endpoints
POST `/mcp` must handle JSON-RPC 2.0:
- `initialize` → return `{"protocolVersion":"2025-11-25","capabilities":{"tools":{}},"serverInfo":{"name":"...","version":"1.0.0"}}`
- `tools/list` → return `{"tools":[{"name":"tool_name","description":"...","inputSchema":{...}}]}`
- `tools/call` → execute the tool and return result
- Empty body → return `{"error":{"code":-32700,"message":"Parse error"}}` (NOT HTTP 500!)

### A2A Endpoints
POST `/a2a` must handle JSON-RPC 2.0:
- Empty body → return `{"error":{"code":-32700,"message":"Parse error"}}` (NOT HTTP 500!)

### OASF Valid Paths (v0.8.0)
Paths are STRICTLY 2-level: `category/skill`. Never use 3-level paths.

**Valid skills:**
- `natural_language_processing/information_retrieval_synthesis`
- `natural_language_processing/natural_language_generation`
- `natural_language_processing/natural_language_understanding`
- `tool_interaction/api_schema_understanding`
- `tool_interaction/workflow_automation`
- `data_engineering/data_transformation_pipeline`
- `evaluation_monitoring/anomaly_detection` (NOT evaluation_AND_monitoring)
- `analytical_skills/mathematical_reasoning`
- `security_privacy/threat_detection`

**Valid domains:**
- `technology/software_engineering`
- `technology/blockchain`
- `finance_and_business/finance`
- `finance_and_business/investment_services`

### Critical Rules (Common Mistakes)
1. **A2A endpoint** in services MUST point to `/.well-known/agent-card.json` (discovery URL), NOT `/a2a`
2. **CAIP-10 format** for all addresses: `eip155:{chainId}:0x{address}`
3. **Field name is `services`**, NOT `endpoints`
4. **No non-verifiable services**: Do NOT put `x402-signals` or `telegram-bot` in services (causes scanner Service=0)
5. **Single source of truth**: Load registration.json from file, serve it at all discovery paths
6. **Empty body handling**: `/mcp` and `/a2a` must return -32700 on empty POST, not HTTP 500
7. **MCP version**: Use `2025-11-25`, not `2025-06-18`
8. **OASF paths**: 2-level only. `evaluation_monitoring` not `evaluation_and_monitoring`

### Stack Preference
- TypeScript: Use Hono framework
- Python: Use FastAPI framework
- Include Dockerfile + railway.toml for Railway deployment

### My Agent
Help me build an agent that: [DESCRIBE WHAT YOUR AGENT DOES HERE]

---

## Example Usage

Paste the prompt above, then add at the end:

> Help me build an agent that monitors DeFi lending rates across Aave, Compound, and Maker on Avalanche. It should expose MCP tools for querying current rates, historical trends, and liquidation risks.

The LLM will generate:
1. Complete server code with all required endpoints
2. registration.json with correct metadata
3. MCP tool definitions
4. Dockerfile for deployment
