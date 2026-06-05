// Key Vault: Dify の .env に注入するシークレットを集約する。
// RBAC 認可を有効化し、VM のマネージド ID に "Key Vault Secrets User" を付与する。

@description('リソースのデプロイ先リージョン。')
param location string

@description('リソース名のプレフィックス。')
param namePrefix string

@description('Secrets 読み取りを許可する VM マネージド ID の principalId。')
param vmPrincipalId string

@description('論理削除されたボールトのパージ防止を有効化する。')
param enablePurgeProtection bool = false

// Key Vault 名はグローバル一意・24 文字以内・英数字
var keyVaultName = take('${toLower(replace(namePrefix, '-', ''))}kv${uniqueString(resourceGroup().id)}', 24)

// "Key Vault Secrets User" ロール定義 ID（組み込み）
var secretsUserRoleId = '4633458b-17de-408a-b874-0445c86b69e6'

resource keyVault 'Microsoft.KeyVault/vaults@2024-11-01' = {
  name: keyVaultName
  location: location
  properties: {
    sku: {
      family: 'A'
      name: 'standard'
    }
    tenantId: subscription().tenantId
    enableRbacAuthorization: true
    enableSoftDelete: true
    enablePurgeProtection: enablePurgeProtection ? true : null
    publicNetworkAccess: 'Enabled'
  }
}

resource secretsUserAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(keyVault.id, vmPrincipalId, secretsUserRoleId)
  scope: keyVault
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', secretsUserRoleId)
    principalId: vmPrincipalId
    principalType: 'ServicePrincipal'
  }
}

output keyVaultName string = keyVault.name
output keyVaultUri string = keyVault.properties.vaultUri
