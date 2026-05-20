@description('Principal ID of the AI Foundry system-assigned managed identity')
param aiFoundryPrincipalId string

@description('Principal ID of the AI Foundry project system-assigned managed identity')
param aiFoundryProjectPrincipalId string

@description('Resource ID of the AI Search service')
param searchId string

@description('Resource ID of the AI Foundry (Cognitive Services) account')
param aiFoundryId string

@description('Principal ID of the jumpbox VM system-assigned managed identity')
param jumpboxPrincipalId string

// Built-in role definition IDs
var searchIndexDataContributorRoleId = '8ebe5a00-799e-43f5-93ac-243d3dce84a7'
var searchServiceContributorRoleId = '7ca78c08-252a-4471-8644-bb5ff32d4ba0'
var cognitiveServicesOpenAIUserRoleId = '5e0bd9bd-7b93-4f28-af87-19fc36ad61bd'

resource searchResource 'Microsoft.Search/searchServices@2025-05-01' existing = {
  name: last(split(searchId, '/'))
}

resource aiFoundryResource 'Microsoft.CognitiveServices/accounts@2025-06-01' existing = {
  name: last(split(aiFoundryId, '/'))
}

// --- AI Foundry MI → Search ---

resource searchIndexDataContributorFoundry 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(searchId, aiFoundryPrincipalId, searchIndexDataContributorRoleId)
  scope: searchResource
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', searchIndexDataContributorRoleId)
    principalId: aiFoundryPrincipalId
    principalType: 'ServicePrincipal'
  }
}

resource searchServiceContributorFoundry 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(searchId, aiFoundryPrincipalId, searchServiceContributorRoleId)
  scope: searchResource
  dependsOn: [
    searchIndexDataContributorFoundry
  ]
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', searchServiceContributorRoleId)
    principalId: aiFoundryPrincipalId
    principalType: 'ServicePrincipal'
  }
}

// --- Jumpbox VM MI → Search (so it can create the index and upload docs) ---

resource searchIndexDataContributorVm 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(searchId, jumpboxPrincipalId, searchIndexDataContributorRoleId)
  scope: searchResource
  dependsOn: [
    searchServiceContributorFoundry
  ]
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', searchIndexDataContributorRoleId)
    principalId: jumpboxPrincipalId
    principalType: 'ServicePrincipal'
  }
}

resource searchServiceContributorVm 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(searchId, jumpboxPrincipalId, searchServiceContributorRoleId)
  scope: searchResource
  dependsOn: [
    searchIndexDataContributorVm
  ]
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', searchServiceContributorRoleId)
    principalId: jumpboxPrincipalId
    principalType: 'ServicePrincipal'
  }
}

// --- Jumpbox VM MI → AI Foundry (so it can call embeddings) ---

resource cognitiveOpenAIUserVm 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(aiFoundryId, jumpboxPrincipalId, cognitiveServicesOpenAIUserRoleId)
  scope: aiFoundryResource
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', cognitiveServicesOpenAIUserRoleId)
    principalId: jumpboxPrincipalId
    principalType: 'ServicePrincipal'
  }
}

// --- AI Foundry PROJECT MI → Search ---
// Connections shown in the Foundry portal authenticate with the project's
// managed identity (not the parent account's). Agents calling the AI Search
// tool need the project MI to have data-plane access to the index.

resource searchIndexDataContributorProject 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(searchId, aiFoundryProjectPrincipalId, searchIndexDataContributorRoleId)
  scope: searchResource
  dependsOn: [
    searchServiceContributorVm
  ]
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', searchIndexDataContributorRoleId)
    principalId: aiFoundryProjectPrincipalId
    principalType: 'ServicePrincipal'
  }
}

resource searchServiceContributorProject 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(searchId, aiFoundryProjectPrincipalId, searchServiceContributorRoleId)
  scope: searchResource
  dependsOn: [
    searchIndexDataContributorProject
  ]
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', searchServiceContributorRoleId)
    principalId: aiFoundryProjectPrincipalId
    principalType: 'ServicePrincipal'
  }
}
