// Azure OpenAI: Dify から利用するモデルプロバイダー。
// キー認証(既定)を有効のまま作成し、gpt-4.1 をデプロイする。
// ※ gpt-4.1 の GlobalStandard 枠があるリージョン（eastus 等）に作成すること。

@description('Azure OpenAI アカウントのリージョン。')
param location string

@description('Azure OpenAI アカウント名（グローバル一意・カスタムサブドメインに使用）。')
param accountName string

@description('デプロイするモデル名（= Dify のデプロイ名）。')
param modelName string = 'gpt-4.1'

@description('モデルのバージョン。')
param modelVersion string = '2025-04-14'

@description('デプロイ SKU（GlobalStandard 等）。')
param deploymentSku string = 'GlobalStandard'

@description('デプロイ容量（1000 TPM 単位。eastus の gpt-4.1 GlobalStandard 上限は 1000）。')
param capacity int = 10

resource account 'Microsoft.CognitiveServices/accounts@2024-10-01' = {
  name: accountName
  location: location
  kind: 'OpenAI'
  sku: {
    name: 'S0'
  }
  properties: {
    customSubDomainName: accountName
    publicNetworkAccess: 'Enabled'
    // disableLocalAuth は未設定（= false, キー認証有効）。Dify はキーで接続する。
  }
}

resource deployment 'Microsoft.CognitiveServices/accounts/deployments@2024-10-01' = {
  parent: account
  name: modelName
  sku: {
    name: deploymentSku
    capacity: capacity
  }
  properties: {
    model: {
      format: 'OpenAI'
      name: modelName
      version: modelVersion
    }
  }
}

output endpoint string = account.properties.endpoint
output accountName string = account.name
output deploymentName string = deployment.name
