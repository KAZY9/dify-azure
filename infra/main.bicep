// Dify on Azure VM — ルートテンプレート（サブスクリプションスコープ）
// リソースグループを作成し、その RG にスコープして resources.bicep を呼び出す。
//   az deployment sub create -l <location> -f infra/main.bicep -p infra/main.bicepparam

targetScope = 'subscription'

@description('作成するリソースグループ名。')
param resourceGroupName string = 'dify-rg'

@description('リソースグループおよび全リソースのリージョン。')
param location string = 'japaneast'

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

@description('VM サイズ。検証用途は Standard_B2ms（2 vCPU / 8 GiB, バースト可能）。')
param vmSize string = 'Standard_B2ms'

@description('OS ディスクサイズ（GB）。')
param osDiskSizeGB int = 64

@description('OS ディスクのストレージ種別。検証用途は StandardSSD_LRS が低コスト。')
@allowed([
  'Standard_LRS'
  'StandardSSD_LRS'
  'Premium_LRS'
])
param osDiskStorageAccountType string = 'StandardSSD_LRS'

@description('Key Vault をデプロイし、VM のマネージド ID に Secrets 読み取り権限を付与する。')
param deployKeyVault bool = true

@description('夜間の自動停止(deallocate)を有効化する。開始は手動運用（az vm start）。')
param enableAutoShutdown bool = true

@description('自動停止の時刻（HHmm 形式, JST）。例: 1900 = 19:00。')
param autoShutdownTime string = '1900'

@description('初回起動時に自己署名証明書で HTTPS を有効化する。ドメイン取得後は dify-enable-tls.sh で Let\'s Encrypt に差し替え。')
param enableTls bool = true

@description('Let\'s Encrypt 登録用メールアドレス（dify-enable-tls.sh に埋め込む）。')
param certbotEmail string = 'admin@example.com'

// リソースグループを作成
resource rg 'Microsoft.Resources/resourceGroups@2024-11-01' = {
  name: resourceGroupName
  location: location
}

// 作成した RG にスコープしてリソース一式をデプロイ
module resources 'resources.bicep' = {
  name: 'resources'
  scope: rg
  params: {
    location: location
    namePrefix: namePrefix
    adminUsername: adminUsername
    adminPublicKey: adminPublicKey
    allowedSshSourceCidr: allowedSshSourceCidr
    vmSize: vmSize
    osDiskSizeGB: osDiskSizeGB
    osDiskStorageAccountType: osDiskStorageAccountType
    deployKeyVault: deployKeyVault
    enableAutoShutdown: enableAutoShutdown
    autoShutdownTime: autoShutdownTime
    enableTls: enableTls
    certbotEmail: certbotEmail
  }
}

@description('作成されたリソースグループ名。')
output resourceGroupName string = rg.name

@description('VM のパブリック IP アドレス。')
output publicIpAddress string = resources.outputs.publicIpAddress

@description('VM への SSH 接続コマンド。')
output sshCommand string = resources.outputs.sshCommand

@description('VM の手動起動コマンド（夜間自動停止後の利用前に実行）。')
output startCommand string = resources.outputs.startCommand

@description('Dify コンソール URL（TLS 設定前は HTTP）。')
output difyUrl string = resources.outputs.difyUrl

@description('作成された Key Vault 名（未作成なら空）。')
output keyVaultName string = resources.outputs.keyVaultName
