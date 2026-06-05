using './main.bicep'

// テンプレートがこの RG を作成し、その中に一式をデプロイする。
param resourceGroupName = 'dify-rg'
param location = 'japaneast'

param namePrefix = 'dify'
param adminUsername = 'azureuser'

// 自分のグローバル IP に絞る（例: 203.0.113.10/32）。0.0.0.0/0 は SSH を全開放するので避ける。
param allowedSshSourceCidr = '<YOUR_IP>/32'

// SSH 公開鍵の内容を貼り付け（例: `cat ~/.ssh/id_ed25519.pub`）。
param adminPublicKey = '<PASTE_SSH_PUBLIC_KEY>'

// 検証 + エージェント品質テスト用。2 vCPU / 8 GiB（B2ms）で Dify 9 コンテナ + 同時負荷の RAM 余裕を確保。
// 未使用時は停止(deallocate)運用でコンピューティング課金を抑える想定。
param vmSize = 'Standard_B2ms'
param osDiskSizeGB = 64
param osDiskStorageAccountType = 'StandardSSD_LRS'
param deployKeyVault = true

// 「使う前に手動 az vm start、夜は自動 stop」運用。停止は毎日 19:00 JST。
param enableAutoShutdown = true
param autoShutdownTime = '1900'

// TLS: ドメイン未取得のため初回は自己署名証明書で HTTPS 化（ブラウザ警告あり）。
// ドメイン取得後に VM 上で `sudo /opt/dify-enable-tls.sh <domain>` を実行して Let's Encrypt に差し替える。
param enableTls = true
param certbotEmail = 'kazu.m.sora9@gmail.com'
