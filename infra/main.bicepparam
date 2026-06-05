using './main.bicep'

// テンプレートがこの RG を作成し、その中に一式をデプロイする。
param resourceGroupName = 'dify-rg'
param location = 'japaneast'

param namePrefix = 'dify'
param adminUsername = 'azureuser'

// マシン固有・プライバシー性のある値は infra/.env から読み込む（.gitignore 済み・コミットしない）。
// デプロイ前に環境変数を読み込むこと:  set -a; source infra/.env; set +a
// SSH 許可元 CIDR（自分のグローバル IP に絞る。0.0.0.0/0 は全開放なので避ける）。
param allowedSshSourceCidr = readEnvironmentVariable('DIFY_SSH_CIDR')
// SSH 公開鍵（公開鍵自体は機密ではないが、公開リポジトリに残さないため env 経由にする）。
param adminPublicKey = readEnvironmentVariable('DIFY_SSH_PUBKEY')

// 検証 + エージェント品質テスト用。2 vCPU / 8 GiB で Dify 9 コンテナ + 同時負荷の RAM 余裕を確保。
// 未使用時は停止(deallocate)運用でコンピューティング課金を抑える想定。
// ※ japaneast/当サブスクリプションでは B2ms=在庫制限, Dsv5=クォータ0, Dsv4=SKU制限のため、
//   在庫・クォータとも空いている DSv3 世代の Standard_D2s_v3 を採用。
param vmSize = 'Standard_D2s_v3'
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

// Dify のバージョン固定（git タグ）。更新時はこの値を上げる。2.0.0 はまだ beta。
param difyVersion = '1.14.2'

// difySecretKey は未指定なら newGuid() で自動生成され Key Vault(dify-secret-key) に格納される。
// 固定したい場合のみ: param difySecretKey = '<強固なランダム文字列>'
