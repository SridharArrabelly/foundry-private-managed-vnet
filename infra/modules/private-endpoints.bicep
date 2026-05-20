@description('Azure region for deployment')
param location string

@description('Resource name prefix')
param prefix string

@description('Subnet ID for private endpoints')
param peSubnetId string

@description('VNet ID for DNS zone links')
param vnetId string

@description('AI Foundry resource ID')
param aiFoundryId string

@description('AI Search resource ID')
param searchId string

// --- Private DNS Zones ---

resource dnsZoneFoundry 'Microsoft.Network/privateDnsZones@2024-06-01' = {
  name: 'privatelink.cognitiveservices.azure.com'
  location: 'global'
}

resource dnsZoneOpenAI 'Microsoft.Network/privateDnsZones@2024-06-01' = {
  name: 'privatelink.openai.azure.com'
  location: 'global'
}

resource dnsZoneAIServices 'Microsoft.Network/privateDnsZones@2024-06-01' = {
  name: 'privatelink.services.ai.azure.com'
  location: 'global'
}

resource dnsZoneSearch 'Microsoft.Network/privateDnsZones@2024-06-01' = {
  name: 'privatelink.search.windows.net'
  location: 'global'
}

// --- VNet Links ---

resource vnetLinkFoundry 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2024-06-01' = {
  parent: dnsZoneFoundry
  name: 'link-${prefix}-foundry'
  location: 'global'
  properties: {
    virtualNetwork: {
      id: vnetId
    }
    registrationEnabled: false
  }
}

resource vnetLinkOpenAI 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2024-06-01' = {
  parent: dnsZoneOpenAI
  name: 'link-${prefix}-openai'
  location: 'global'
  properties: {
    virtualNetwork: {
      id: vnetId
    }
    registrationEnabled: false
  }
}

resource vnetLinkAIServices 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2024-06-01' = {
  parent: dnsZoneAIServices
  name: 'link-${prefix}-aiservices'
  location: 'global'
  properties: {
    virtualNetwork: {
      id: vnetId
    }
    registrationEnabled: false
  }
}

resource vnetLinkSearch 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2024-06-01' = {
  parent: dnsZoneSearch
  name: 'link-${prefix}-search'
  location: 'global'
  properties: {
    virtualNetwork: {
      id: vnetId
    }
    registrationEnabled: false
  }
}

// --- Private Endpoints ---

resource peFoundry 'Microsoft.Network/privateEndpoints@2024-07-01' = {
  name: 'pep-${prefix}-foundry'
  location: location
  properties: {
    subnet: {
      id: peSubnetId
    }
    privateLinkServiceConnections: [
      {
        name: 'plsc-${prefix}-foundry'
        properties: {
          privateLinkServiceId: aiFoundryId
          groupIds: [
            'account'
          ]
        }
      }
    ]
  }
}

resource peSearch 'Microsoft.Network/privateEndpoints@2024-07-01' = {
  name: 'pep-${prefix}-search'
  location: location
  // Serialize PE creation to avoid IfMatchPreconditionFailed: both PEs target
  // the same subnet and ARM PATCHes the subnet on each PE create.
  dependsOn: [
    peFoundry
  ]
  properties: {
    subnet: {
      id: peSubnetId
    }
    privateLinkServiceConnections: [
      {
        name: 'plsc-${prefix}-search'
        properties: {
          privateLinkServiceId: searchId
          groupIds: [
            'searchService'
          ]
        }
      }
    ]
  }
}

// --- DNS Zone Groups (auto-register A records) ---

resource dnsGroupFoundry 'Microsoft.Network/privateEndpoints/privateDnsZoneGroups@2024-07-01' = {
  parent: peFoundry
  name: 'default'
  properties: {
    privateDnsZoneConfigs: [
      {
        name: 'config-foundry'
        properties: {
          privateDnsZoneId: dnsZoneFoundry.id
        }
      }
      {
        name: 'config-openai'
        properties: {
          privateDnsZoneId: dnsZoneOpenAI.id
        }
      }
      {
        name: 'config-aiservices'
        properties: {
          privateDnsZoneId: dnsZoneAIServices.id
        }
      }
    ]
  }
}

resource dnsGroupSearch 'Microsoft.Network/privateEndpoints/privateDnsZoneGroups@2024-07-01' = {
  parent: peSearch
  name: 'default'
  properties: {
    privateDnsZoneConfigs: [
      {
        name: 'config-search'
        properties: {
          privateDnsZoneId: dnsZoneSearch.id
        }
      }
    ]
  }
}
