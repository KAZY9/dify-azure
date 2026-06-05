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

## シークレット（Key Vault → .env）

- Bicep が Key Vault にシークレット `dify-secret-key`（既定値は `newGuid()`）を作成する。固定値にしたい場合は `main.bicepparam` で `difySecretKey` を指定。
- VM はマネージド ID（"Key Vault Secrets User" 付与済み）で起動時に `dify-secret-key` を取得し、Dify の `.env` の `SECRET_KEY` に注入する（RBAC 伝播待ちのリトライ付き）。取得できない場合は `openssl rand` で自動生成してフォールバック。
- Azure OpenAI などモデルプロバイダーの資格情報は通常 Dify の Web コンソールから設定する（`.env` ではなく DB に暗号化保存）。同様の方式で `.env` 注入したい場合は `cloud-init.yaml` の TODO 箇所を拡張する。
- ⚠️ シークレット作成のため、デプロイ実行者(deployer)に "Key Vault Secrets Officer" を付与する。**デプロイにはロール割り当て権限（Owner または User Access Administrator）が必要**。

## バージョン固定

- Dify は `difyVersion`（既定 `1.14.2`）の git タグで固定して clone する（`git clone --depth 1 --branch <tag>`）。
- 更新時は `main.bicepparam` の `difyVersion` を上げる。`main` を指定すると最新追従（非推奨）。
- 最新タグの確認: `git ls-remote --tags https://github.com/langgenius/dify.git`。

## 検証（lint / build）

```bash
az bicep lint --file infra/main.bicep
az bicep build --file infra/main.bicep   # ARM への変換可否を確認
```

## 補足・残タスク

- **TLS 化**: 初回は自己署名証明書で HTTPS 化済み（上記「TLS / HTTPS」参照）。ドメイン取得後に Let's Encrypt へ差し替える。
- **SSH 元の制限**: `allowedSshSourceCidr` は必ず自分の IP に絞る。Bastion 利用ならパブリック IP を外す構成も検討。
- **LLMOps 評価基盤**: `evals/`（Langfuse / Ragas）は未実装。
