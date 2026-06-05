// Key Vault: Dify の .env に注入するシークレットを集約する。
// RBAC 認可を有効化し、VM のマネージド ID に "Key Vault Secrets User"(読み取り) を付与する。
// SECRET_KEY(dify-secret-key) を格納し、シークレット作成のため deployer に "Secrets Officer" を付与する。

@description('リソースのデプロイ先リージョン。')
param location string

@description('Key Vault 名（グローバル一意・3〜24 文字）。')
param keyVaultName string

@description('Secrets 読み取りを許可する VM マネージド ID の principalId。')
param vmPrincipalId string

@description('Dify の SECRET_KEY として格納する値。既定は新規 GUID。')
@secure()
param difySecretKey string

@description('論理削除されたボールトのパージ防止を有効化する。')
param enablePurgeProtection bool = false

// 組み込みロール定義 ID
var secretsUserRoleId = '4633458b-17de-408a-b874-0445c86b69e6' // Key Vault Secrets User (読み取り)
var secretsOfficerRoleId = 'b86a8fe4-44ce-4948-aee5-eccb2c155cd7' // Key Vault Secrets Officer (読み書き)

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

// VM のマネージド ID にシークレット読み取りを許可
resource secretsUserAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(keyVault.id, vmPrincipalId, secretsUserRoleId)
  scope: keyVault
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', secretsUserRoleId)
    principalId: vmPrincipalId
    principalType: 'ServicePrincipal'
  }
}

// シークレット作成のため、デプロイ実行者に書き込み権限(Secrets Officer)を付与
resource deployerSecretsOfficer 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(keyVault.id, deployer().objectId, secretsOfficerRoleId)
  scope: keyVault
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', secretsOfficerRoleId)
    principalId: deployer().objectId
  }
}

// Dify の SECRET_KEY を格納（書き込み権限の付与後に作成）
resource difySecret 'Microsoft.KeyVault/vaults/secrets@2024-11-01' = {
  parent: keyVault
  name: 'dify-secret-key'
  properties: {
    value: difySecretKey
  }
  dependsOn: [
    deployerSecretsOfficer
  ]
}

output keyVaultName string = keyVault.name
output keyVaultUri string = keyVault.properties.vaultUri
