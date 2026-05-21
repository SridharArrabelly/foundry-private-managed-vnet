@description('Azure region for deployment')
param location string

@description('Resource name prefix')
param prefix string

@description('Your public IP address to allow portal/API access (leave empty to block all public access)')
param allowedIpAddress string = ''

@description('Name of the AI Search service to wire as a project connection (for managed VNet outbound)')
param searchName string

@description('Resource ID of the AI Search service')
param searchId string

@description('Location of the AI Search service (used in connection metadata)')
param searchLocation string

var accountName = 'ais-${prefix}'

resource aiFoundry 'Microsoft.CognitiveServices/accounts@2025-10-01-preview' = {
  name: accountName
  location: location
  kind: 'AIServices'
  identity: {
    type: 'SystemAssigned'
  }
  sku: {
    name: 'S0'
  }
  properties: {
    customSubDomainName: accountName
    publicNetworkAccess: empty(allowedIpAddress) ? 'Disabled' : 'Enabled'
    allowProjectManagement: true
    networkAcls: {
      defaultAction: 'Deny'
      bypass: 'AzureServices'
      ipRules: empty(allowedIpAddress) ? [] : [
        {
          value: allowedIpAddress
        }
      ]
    }
    // Managed VNet for the Foundry Agent runtime. Microsoft provisions and
    // manages a virtual network behind the scenes; agent + evaluation traffic
    // is isolated to this network. Outbound to private resources (e.g. our
    // private AI Search) is configured via approved outbound rules created
    // automatically when we add the Search connection on the project below.
    networkInjections: [
      {
        scenario: 'agent'
        subnetArmId: ''
        useMicrosoftManagedNetwork: true
      }
    ]
  }
}

// Managed-network settings on the account. AllowOnlyApprovedOutbound is the
// strictest isolation mode: outbound traffic from the agent runtime is only
// permitted to explicitly-approved targets (the project connections below).
#disable-next-line BCP081
resource aiFoundryManagedNetwork 'Microsoft.CognitiveServices/accounts/managednetworks@2025-10-01-preview' = {
  parent: aiFoundry
  name: 'default'
  properties: {
    managedNetwork: {
      IsolationMode: 'AllowOnlyApprovedOutbound'
      managedNetworkKind: 'V2'
      provisionNetworkNow: true
    }
  }
}

// Allow the Foundry account MI to auto-approve managed private endpoints
// created in its managed VNet (e.g. the outbound PE to our private AI Search).
// Built-in role: 'Azure AI Enterprise Network Connection Approver'.
resource networkConnectionApprover 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  scope: resourceGroup()
  name: guid(aiFoundry.id, 'b556d68e-0be0-4f35-a333-ad7ee1ce17ea', resourceGroup().id)
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'b556d68e-0be0-4f35-a333-ad7ee1ce17ea')
    principalId: aiFoundry.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

// --- Foundry Project ---
// Serialize after deployments to avoid IfMatchPreconditionFailed races on the
// parent account (both project and deployments are children of aiFoundry).
resource foundryProject 'Microsoft.CognitiveServices/accounts/projects@2025-10-01-preview' = {
  parent: aiFoundry
  name: '${prefix}-project'
  location: location
  identity: {
    type: 'SystemAssigned'
  }
  properties: {}
  dependsOn: [
    embeddingDeployment
    gpt4MiniDeployment
    aiFoundryManagedNetwork
  ]
}

// AI Search connection on the project. With AAD auth + managed VNet,
// Foundry auto-creates an approved outbound rule (managed private endpoint)
// from its managed VNet to the Search service so the agent runtime can
// reach our private-only Search through a private link.
resource projectSearchConnection 'Microsoft.CognitiveServices/accounts/projects/connections@2025-10-01-preview' = {
  parent: foundryProject
  name: searchName
  properties: {
    category: 'CognitiveSearch'
    target: 'https://${searchName}.search.windows.net'
    authType: 'AAD'
    metadata: {
      ApiType: 'Azure'
      ResourceId: searchId
      location: searchLocation
    }
  }
}

// --- Model Deployments (on the project) ---

resource embeddingDeployment 'Microsoft.CognitiveServices/accounts/deployments@2025-06-01' = {
  parent: aiFoundry
  name: 'text-embedding-3-large'
  sku: {
    name: 'GlobalStandard'
    capacity: 30
  }
  properties: {
    model: {
      format: 'OpenAI'
      name: 'text-embedding-3-large'
      version: '1'
    }
  }
}

resource gpt4MiniDeployment 'Microsoft.CognitiveServices/accounts/deployments@2025-06-01' = {
  parent: aiFoundry
  name: 'gpt-4.1-mini'
  sku: {
    name: 'GlobalStandard'
    capacity: 30
  }
  properties: {
    model: {
      format: 'OpenAI'
      name: 'gpt-4.1-mini'
      version: '2025-04-14'
    }
  }
  dependsOn: [embeddingDeployment]
}

output aiFoundryId string = aiFoundry.id
output aiFoundryName string = aiFoundry.name
output aiFoundryEndpoint string = 'https://${accountName}.cognitiveservices.azure.com'
output aiFoundryPrincipalId string = aiFoundry.identity.principalId
output aiFoundryProjectPrincipalId string = foundryProject.identity.principalId
