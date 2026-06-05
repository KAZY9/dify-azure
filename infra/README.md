# infra — Dify on Azure VM (Bicep)

Dify を Azure VM 上で公式 `docker compose` により稼働させるためのインフラ定義。

## 構成

```
infra/
├── main.bicep            # ルート: 各モジュールを束ねる
├── main.bicepparam       # パラメータ（要編集）
├── cloud-init.yaml       # VM 初回起動時に Docker + Dify を起動
└── modules/
    ├── network.bicep     # VNet / Subnet / NSG / Public IP
    ├── vm.bicep          # NIC / Ubuntu 22.04 VM（SSH 鍵認証・マネージド ID）
    └── keyvault.bicep    # Key Vault + VM への Secrets 読み取りロール付与
```

## 前提

- Azure CLI（`az`）にログイン済み（`az login`）
- Bicep CLI（`az bicep install`）
- SSH 鍵ペア（無ければ `ssh-keygen -t ed25519`）

## デプロイ手順

```bash
# 1. リソースグループを作成
az group create -n dify-rg -l japaneast

# 2. パラメータを編集（allowedSshSourceCidr / adminPublicKey）
#    SSH 公開鍵: cat ~/.ssh/id_ed25519.pub
$EDITOR infra/main.bicepparam

# 3. 適用前に差分を確認
az deployment group what-if -g dify-rg -f infra/main.bicep -p infra/main.bicepparam

# 4. デプロイ
az deployment group create -g dify-rg -f infra/main.bicep -p infra/main.bicepparam

# 5. 出力（publicIpAddress / sshCommand / difyUrl）を確認
#    数分後、difyUrl にアクセスして初期セットアップ
```

## 検証（lint / build）

```bash
az bicep lint --file infra/main.bicep
az bicep build --file infra/main.bicep   # ARM への変換可否を確認
```

## 補足・残タスク

- **TLS 化**: 現状は HTTP(80) 公開。ドメインを割り当て、Nginx + Let's Encrypt(certbot) で HTTPS 化する。
- **シークレット**: `cloud-init.yaml` の TODO のとおり、Key Vault から `SECRET_KEY` や Azure OpenAI のキーを取得して `.env` に反映する処理が未実装。
- **バージョン固定**: `cloud-init.yaml` は Dify を `main` から clone する。本番ではタグ指定で固定する。
- **SSH 元の制限**: `allowedSshSourceCidr` は必ず自分の IP に絞る。Bastion 利用ならパブリック IP を外す構成も検討。
