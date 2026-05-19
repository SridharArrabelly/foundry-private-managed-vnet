# Foundry Network Test

End-to-end private networking test for **Azure AI Foundry** and **Azure AI Search** communicating over private endpoints. Built to validate a client's network configuration before a support call.

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│  VNet: 10.0.0.0/16                                              │
│                                                                  │
│  ┌──────────────────┐  ┌──────────────────┐  ┌───────────────┐ │
│  │ snet-pe          │  │ snet-vm          │  │ AzureBastion  │ │
│  │ 10.0.1.0/24      │  │ 10.0.2.0/24      │  │ 10.0.3.0/26   │ │
│  │                  │  │                  │  │               │ │
│  │ ● PE (Foundry)   │  │ ● Windows 11 VM  │  │ ● Bastion     │ │
│  │ ● PE (AI Search) │  │   (jumpbox)      │  │   (Basic SKU) │ │
│  └──────────────────┘  └──────────────────┘  └───────────────┘ │
│                                                                  │
│  Private DNS Zones (linked to VNet):                            │
│  • privatelink.cognitiveservices.azure.com → AI Foundry PE IP   │
│  • privatelink.search.windows.net → AI Search PE IP             │
└─────────────────────────────────────────────────────────────────┘

                    RBAC (System MI)
    ┌──────────────┐ ──────────────────► ┌──────────────┐
    │ AI Foundry   │  Search Index Data   │  AI Search   │
    │ (AIServices) │  Contributor +       │  (basic SKU) │
    │              │  Search Service      │              │
    │ Models:      │  Contributor         │  Index:      │
    │ • embedding  │                      │  documents-  │
    │   -3-small   │                      │  index       │
    │ • gpt-4.1-   │                      │              │
    │   mini       │                      │              │
    └──────────────┘                      └──────────────┘
```

## Resources Deployed

| Resource | Type | Purpose |
|----------|------|---------|
| VNet | `Microsoft.Network/virtualNetworks` | Hosts all subnets for private connectivity |
| PE Subnet | Subnet (10.0.1.0/24) | Private endpoints for AI services |
| VM Subnet | Subnet (10.0.2.0/24) | Jumpbox VM |
| Bastion Subnet | AzureBastionSubnet (10.0.3.0/26) | Azure Bastion host |
| AI Foundry | `Microsoft.CognitiveServices/accounts` (kind: AIServices) | AI Services with project management |
| Foundry Project | `accounts/projects` | Foundry project for model management |
| text-embedding-3-small | Model deployment (GlobalStandard) | Embedding model for vectorizing documents |
| gpt-4.1-mini | Model deployment (GlobalStandard) | Chat/completion model |
| AI Search | `Microsoft.Search/searchServices` (basic) | Search index for document chunks |
| RBAC: Search Index Data Contributor | Role assignment | Foundry MI → read/write search index data |
| RBAC: Search Service Contributor | Role assignment | Foundry MI → manage search service |
| Private Endpoint (Foundry) | `Microsoft.Network/privateEndpoints` | Private connectivity to AI Foundry |
| Private Endpoint (Search) | `Microsoft.Network/privateEndpoints` | Private connectivity to AI Search |
| Private DNS Zone (Foundry) | `privatelink.cognitiveservices.azure.com` | DNS resolution for Foundry PE |
| Private DNS Zone (Search) | `privatelink.search.windows.net` | DNS resolution for Search PE |
| Windows 11 VM | `Microsoft.Compute/virtualMachines` (Standard_B2ms) | Jumpbox for testing private access |
| Azure Bastion | `Microsoft.Network/bastionHosts` (Basic) | Secure RDP to VM without public IP |

## Prerequisites

- Azure CLI (`az`) installed and authenticated
- Subscription with **Owner** role (or Contributor + RBAC Administrator)
- Python 3.10+ (for the indexing script)

## Deployment

### 1. Deploy Infrastructure

```powershell
cd C:\Users\sarrabelly\Documents\GitHub\foundry-network-test
.\deploy.ps1
```

The script prompts for:
| Parameter | Description |
|-----------|-------------|
| Subscription ID | Target Azure subscription |
| Resource Group | Resource group name (created if it doesn't exist) |
| Location | Azure region (e.g. `australiaeast`, `eastus`) |
| Prefix | Naming prefix for all resources (lowercase, no special chars) |
| Allowed IP | Your public IP for portal access (optional, leave empty for fully private) |
| VM Admin Username | Jumpbox admin user (default: `azureadmin`) |
| VM Admin Password | Jumpbox admin password (12+ chars, upper/lower/number/special) |

### 2. Connect to Jumpbox via Bastion

1. Azure Portal → your resource group → `bas-<prefix>` (Bastion)
2. Click **Connect** → select `vm-<prefix>`
3. Enter admin credentials
4. From the VM, open a browser — you now have private access to:
   - Foundry portal: `https://ai.azure.com`
   - AI Search portal: `https://srch-<prefix>.search.windows.net`

Or via CLI:
```powershell
az network bastion rdp --name bas-<prefix> --resource-group <rg> --target-resource-id $(az vm show -g <rg> -n vm-<prefix> --query id -o tsv)
```

### 3. Run the Indexing Script

From the jumpbox VM (or any machine with VNet access):

```bash
# Install dependencies
pip install -r scripts/requirements.txt

# Update .env with your actual endpoints
# AI_SEARCH_ENDPOINT=https://srch-<prefix>.search.windows.net
# AI_FOUNDRY_ENDPOINT=https://ais-<prefix>.cognitiveservices.azure.com

# Drop .docx files into data/ folder, then:
python scripts/setup_aisearch_index.py
```

## Configuration (.env)

```env
# Azure AI Search
AI_SEARCH_ENDPOINT=https://srch-<prefix>.search.windows.net
AI_SEARCH_INDEX_NAME=documents-index

# Azure AI Foundry / OpenAI
AI_FOUNDRY_ENDPOINT=https://ais-<prefix>.cognitiveservices.azure.com
EMBEDDING_MODEL=text-embedding-3-small

# Chunking settings
CHUNK_SIZE=1000
CHUNK_OVERLAP=200
```

## Project Structure

```
foundry-network-test/
├── .env                          # Configuration (git-ignored)
├── .gitignore
├── deploy.ps1                    # PowerShell deployment script
├── deploy.sh                     # Bash deployment script
├── README.md
├── data/                         # Drop .docx files here for indexing
├── scripts/
│   ├── requirements.txt          # Python dependencies
│   └── setup_aisearch_index.py   # Creates index, chunks, embeds, uploads
└── infra/
    ├── main.bicep                # Orchestrator (resource group scope)
    └── modules/
        ├── network.bicep         # VNet + subnets (PE, VM, Bastion)
        ├── ai-foundry.bicep      # AI Services + project + model deployments
        ├── ai-search.bicep       # AI Search (basic SKU)
        ├── role-assignments.bicep # RBAC: Foundry MI → Search
        ├── private-endpoints.bicep # PEs + DNS zones + VNet links
        └── jumpbox.bicep         # Windows VM + Azure Bastion
```

## Network Flow

1. **Foundry → AI Search**: Uses system-assigned managed identity over private endpoint. Traffic stays within Azure backbone via RBAC + private link.
2. **You → Foundry/Search portals**: Connect to jumpbox VM via Bastion → VM resolves private DNS → traffic hits private endpoint IPs on the VNet.
3. **Indexing script**: Runs on the jumpbox (or VNet-connected machine), authenticates via `DefaultAzureCredential`, talks to both services over private endpoints.

## Troubleshooting

| Issue | Fix |
|-------|-----|
| "Private network access required" in Foundry portal | Access from jumpbox VM via Bastion, or add your IP to `allowedIpAddress` param |
| DNS not resolving to private IP | Verify private DNS zones are linked to VNet: Portal → DNS Zone → Virtual network links |
| RBAC errors (403) | Wait 5-10 min after deployment for role assignments to propagate |
| Bastion can't connect | Ensure `AzureBastionSubnet` exists with /26 prefix, Bastion takes ~5 min to provision |
| Indexing script timeout | Ensure you're running from a machine on the VNet (jumpbox) |

## Cleanup

```powershell
az group delete --name <resource-group> --yes --no-wait
```
