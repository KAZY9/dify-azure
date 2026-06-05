# infra — Dify on Azure VM (Bicep)

Dify を Azure VM 上で公式 `docker compose` により稼働させるためのインフラ定義。

## 構成

```
infra/
├── main.bicep            # ルート(サブスクリプションスコープ): RG 作成 → resources.bicep 呼び出し
├── resources.bicep       # RG スコープ: network/vm/keyvault モジュールを束ねる
├── main.bicepparam       # パラメータ（要編集）
├── cloud-init.yaml       # VM 初回起動時に Docker + Dify を起動
└── modules/
    ├── network.bicep     # VNet / Subnet / NSG / Public IP
    ├── vm.bicep          # NIC / Ubuntu 22.04 VM（SSH 鍵認証・マネージド ID・自動停止）
    └── keyvault.bicep    # Key Vault + VM への Secrets 読み取りロール付与
```

`main.bicep` がリソースグループ（既定 `dify-rg` / `japaneast`）自体を作成するため、事前の `az group create` は不要。

## 前提

- Azure CLI（`az`）にログイン済み（`az login`）
- Bicep CLI（`az bicep install`）
- SSH 鍵ペア（無ければ `ssh-keygen -t ed25519`）

## デプロイ手順

サブスクリプションスコープでデプロイする（RG も含めて作成されるため `az group create` は不要）。

```bash
# 1. パラメータを編集（allowedSshSourceCidr / adminPublicKey、必要なら resourceGroupName / location）
#    SSH 公開鍵: cat ~/.ssh/id_ed25519.pub
$EDITOR infra/main.bicepparam

# 2. 適用前に差分を確認（-l はメタデータ保存先リージョン）
az deployment sub what-if -l japaneast -f infra/main.bicep -p infra/main.bicepparam

# 3. デプロイ（RG 作成 → RG 内に一式作成）
az deployment sub create -l japaneast -f infra/main.bicep -p infra/main.bicepparam

# 4. 出力（resourceGroupName / publicIpAddress / sshCommand / difyUrl）を確認
#    数分後、difyUrl にアクセスして初期セットアップ
```

> 注: サブスクリプションスコープのデプロイには RG 作成権限（サブスクリプションへの Contributor 等）が必要。

## 運用（起動・停止）

検証用途のため「**使う前に手動起動、夜 19:00 JST に自動停止**」で運用する。

```bash
# 利用前に手動で起動（夜間の自動停止後）
az vm start -g dify-rg -n dify-vm        # デプロイ出力 startCommand にも表示される

# 即時停止したい場合（deallocate = コンピューティング課金を止める）
az vm deallocate -g dify-rg -n dify-vm
```

- 自動停止は毎日 **19:00 JST**（`autoShutdownTime` / `enableAutoShutdown` で変更可）。Auto-shutdown は停止のみで、**開始は行わない**。
- 停止(deallocate)中も **OS ディスクと Static Public IP の課金は継続**する（合計 約 $8〜9/月）。
- Public IP は **Static** のため、停止→起動で **IP は変わらない**。
- Dify コンテナは `restart: always` + Docker 自動起動により、**起動後に自動復帰**する（データは名前付きボリュームに永続）。

## TLS / HTTPS

ドメイン未取得のため **2 段構え**で TLS 化する。

### 1. 初回: 自己署名証明書（自動）

`enableTls = true`（既定）のとき、cloud-init が初回起動時に自己署名証明書を生成し HTTPS を有効化する。

- アクセス: `https://<publicIpAddress>`（デプロイ出力 `difyUrl`）
- ⚠️ 正規 CA の証明書ではないため**ブラウザ警告が出る**（暗号化自体は有効）。検証用途では許容、本番では下記の Let's Encrypt に差し替える。

### 2. ドメイン取得後: Let's Encrypt（手動）

ドメインを取得し、A レコードを VM のパブリック IP に向けて DNS 伝播を確認したら、VM 上で実行する。

```bash
# A レコード（example.com → publicIpAddress）設定 & 伝播確認後
ssh azureuser@<publicIpAddress>
sudo /opt/dify-enable-tls.sh example.com    # certbotEmail はデプロイ時に埋め込み済み
```

- 証明書は Let's Encrypt（certbot）で取得し、以後 `https://example.com` で正規証明書になる。
- 更新（cron 化推奨）: `cd /opt/dify/docker && docker compose exec certbot certbot renew && docker compose exec nginx nginx -s reload`
- ※ certbot 周りの手順は Dify 公式 `docker/certbot/README.md` に準拠。Dify のバージョンによりファイル名・手順が異なる場合があるため、失敗時は同 README を参照。

## 検証（lint / build）

```bash
az bicep lint --file infra/main.bicep
az bicep build --file infra/main.bicep   # ARM への変換可否を確認
```

## 補足・残タスク

- **TLS 化**: 初回は自己署名証明書で HTTPS 化済み（上記「TLS / HTTPS」参照）。ドメイン取得後に Let's Encrypt へ差し替える。
- **シークレット**: `cloud-init.yaml` の TODO のとおり、Key Vault から `SECRET_KEY` や Azure OpenAI のキーを取得して `.env` に反映する処理が未実装。
- **バージョン固定**: `cloud-init.yaml` は Dify を `main` から clone する。本番ではタグ指定で固定する。
- **SSH 元の制限**: `allowedSshSourceCidr` は必ず自分の IP に絞る。Bastion 利用ならパブリック IP を外す構成も検討。
