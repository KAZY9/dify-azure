// Dify on Azure VM — ルートテンプレート
// ネットワーク / VM / Key Vault の各モジュールを束ねてデプロイする。
//   az deployment group create -g <rg> -f infra/main.bicep -p infra/main.bicepparam

targetScope = 'resourceGroup'

@description('全リソースのデプロイ先リージョン。')
param location string = resourceGroup().location

@description('リソース名のプレフィックス。')
@minLength(2)
@maxLength(16)
param namePrefix string = 'dify'

@description('VM の管理者ユーザー名。')
param adminUsername string = 'azureuser'

@description('管理者ユーザーの SSH 公開鍵（id_ed25519.pub などの内容）。公開鍵なので機密ではない。')
param adminPublicKey string

@description('SSH(22) を許可する送信元 CIDR。自分の IP に絞ること（例: 203.0.113.10/32）。')
param allowedSshSourceCidr string

@description('VM サイズ。Dify は最低 4 vCPU / 16 GiB を推奨。')
param vmSize string = 'Standard_D4s_v5'

@description('OS ディスクサイズ（GB）。')
param osDiskSizeGB int = 64

@description('Key Vault をデプロイし、VM のマネージド ID に Secrets 読み取り権限を付与する。')
param deployKeyVault bool = true

module network 'modules/network.bicep' = {
  name: 'network'
  params: {
    location: location
    namePrefix: namePrefix
    allowedSshSourceCidr: allowedSshSourceCidr
  }
}

module vm 'modules/vm.bicep' = {
  name: 'vm'
  params: {
    location: location
    namePrefix: namePrefix
    subnetId: network.outputs.subnetId
    publicIpId: network.outputs.publicIpId
    adminUsername: adminUsername
    adminPublicKey: adminPublicKey
    vmSize: vmSize
    osDiskSizeGB: osDiskSizeGB
    // cloud-init は main.bicep からの相対パスで読み込む
    customData: loadFileAsBase64('cloud-init.yaml')
  }
}

module keyVault 'modules/keyvault.bicep' = if (deployKeyVault) {
  name: 'keyvault'
  params: {
    location: location
    namePrefix: namePrefix
    vmPrincipalId: vm.outputs.principalId
  }
}

@description('VM のパブリック IP アドレス。')
output publicIpAddress string = network.outputs.publicIpAddress

@description('VM への SSH 接続コマンド。')
output sshCommand string = 'ssh ${adminUsername}@${network.outputs.publicIpAddress}'

@description('Dify コンソール URL（TLS 設定前は HTTP）。')
output difyUrl string = 'http://${network.outputs.publicIpAddress}'

@description('作成された Key Vault 名（未作成なら空）。')
output keyVaultName string = deployKeyVault ? keyVault.outputs.keyVaultName : ''
