// Dify on Azure VM — リソースグループ内のリソース一式
// main.bicep（サブスクリプションスコープ）から、作成済み RG にスコープして呼び出される。
// network / vm / keyvault モジュールを束ねる。

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

@description('固定する Dify のバージョン（git タグ）。main で最新を追従。')
param difyVersion string = '1.14.2'

@description('Dify の SECRET_KEY として Key Vault に格納する値。既定は新規 GUID。')
@secure()
param difySecretKey string = newGuid()

// Key Vault 名（モジュールと cloud-init で同じ名前を使うためここで一度だけ算出）。
// グローバル一意・24 文字以内・英数字。
var keyVaultName = deployKeyVault ? take('${toLower(replace(namePrefix, '-', ''))}kv${uniqueString(resourceGroup().id)}', 24) : ''

// cloud-init のプレースホルダを置換して base64 化する。
// 関数の評価は resources.bicep からの相対パス（cloud-init.yaml は同 infra/ 配下）。
var cloudInitCustomData = base64(replace(replace(replace(replace(
  loadTextContent('cloud-init.yaml'),
  '__ENABLE_TLS__', (enableTls ? 'true' : 'false')),
  '__CERTBOT_EMAIL__', certbotEmail),
  '__DIFY_VERSION__', difyVersion),
  '__KEYVAULT_NAME__', keyVaultName))

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
    osDiskStorageAccountType: osDiskStorageAccountType
    enableAutoShutdown: enableAutoShutdown
    autoShutdownTime: autoShutdownTime
    customData: cloudInitCustomData
  }
}

module keyVault 'modules/keyvault.bicep' = if (deployKeyVault) {
  name: 'keyvault'
  params: {
    location: location
    keyVaultName: keyVaultName
    vmPrincipalId: vm.outputs.principalId
    difySecretKey: difySecretKey
  }
}

@description('VM のパブリック IP アドレス。')
output publicIpAddress string = network.outputs.publicIpAddress

@description('VM への SSH 接続コマンド。')
output sshCommand string = 'ssh ${adminUsername}@${network.outputs.publicIpAddress}'

@description('VM の手動起動コマンド（夜間自動停止後の利用前に実行）。')
output startCommand string = 'az vm start -g ${resourceGroup().name} -n ${vm.outputs.vmName}'

@description('Dify コンソール URL（enableTls 時は自己署名 HTTPS、ブラウザ警告あり）。')
output difyUrl string = enableTls ? 'https://${network.outputs.publicIpAddress}' : 'http://${network.outputs.publicIpAddress}'

@description('作成された Key Vault 名（未作成なら空）。')
output keyVaultName string = keyVault.?outputs.keyVaultName ?? ''
