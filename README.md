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
| text-embedding-3-large | Model deployment (GlobalStandard) | Embedding model for vectorizing documents (3072 dims) |
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

- [Azure Developer CLI (`azd`)](https://learn.microsoft.com/azure/developer/azure-developer-cli/install-azd) installed
- Azure CLI (`az`) installed and authenticated (used by `azd` for some operations)
- Subscription with **Owner** role (or Contributor + RBAC Administrator)
- Python 3.10+ (for the indexing script)

## Deployment

### 1. Deploy Infrastructure

```bash
# First time only: log in and create an environment
azd auth login
azd env new <your-env-name>     # pick any name, e.g. foundry-net-dev

# (Optional) set non-default values BEFORE running azd up
azd env set ALLOWED_IP_ADDRESS  <your.public.ip>
azd env set VM_ADMIN_USERNAME   azureadmin
azd env set PREFIX              <lowercase-prefix>   # defaults to env name

# Deploy
azd up
```

`azd up` will prompt for the Azure subscription, location, and the required `vmAdminPassword` (stored securely, not written to disk). All other values come from the azd environment.

After provisioning succeeds, the `postprovision` hook runs `scripts/setup_aisearch_index.py` **on the jumpbox VM** via `az vm run-command`. The hook itself runs wherever you invoked `azd up` (your machine or Cloud Shell); it bootstraps Python on the VM, downloads this repo from GitHub, and runs the indexer using the VM's system-assigned managed identity (which has been granted Search + Foundry RBAC by the deployment).

This works the same from Cloud Shell as from a local machine — `ALLOWED_IP_ADDRESS` does **not** need to be set, because all traffic to the private endpoints originates from the jumpbox (which is on the VNet).

Assumption: this GitHub repo is public (so the jumpbox can download it via HTTPS without auth). If you fork to a private repo, replace the download step in `scripts/jumpbox-bootstrap.ps1` accordingly.

Environment variables consumed by `infra/main.parameters.json`:

| Variable | Required | Description |
|----------|----------|-------------|
| `AZURE_ENV_NAME` | yes (set by `azd env new`) | Used to name the resource group (`rg-<env>`) and tag resources |
| `AZURE_LOCATION` | yes (prompted by `azd up`) | Azure region (e.g. `australiaeast`, `eastus`) |
| `PREFIX` | no | Resource name prefix (lowercase, no special chars). Defaults to `AZURE_ENV_NAME` |
| `ALLOWED_IP_ADDRESS` | no | Your public IP for portal access. Empty = fully private |
| `VM_ADMIN_USERNAME` | no | Jumpbox admin user (default: `azureadmin`) |
| `VM_ADMIN_PASSWORD` | yes (prompted) | Jumpbox admin password (12+ chars, upper/lower/number/special) |

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
EMBEDDING_MODEL=text-embedding-3-large
EMBEDDING_DIMENSIONS=3072

# Chunking settings
CHUNK_SIZE=1000
CHUNK_OVERLAP=200
```

## Project Structure

```
foundry-network-test/
├── .env                          # Configuration (git-ignored)
├── .azure/                       # azd environment state (git-ignored)
├── .gitignore
├── azure.yaml                    # azd project definition
├── README.md
├── data/                         # Drop .docx files here for indexing
├── scripts/
│   ├── requirements.txt          # Python dependencies
│   └── setup_aisearch_index.py   # Creates index, chunks, embeds, uploads
└── infra/
    ├── main.bicep                # Subscription-scope entry point (creates RG)
    ├── main.parameters.json      # azd → bicep parameter bindings
    ├── resources.bicep           # Resource-group-scope orchestrator
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

```bash
azd down --purge --force
```

`--purge` permanently removes soft-deleted Cognitive Services / Key Vault resources so the prefix can be reused. Omit `--force` if you want to be prompted for confirmation.
