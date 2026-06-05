# CLAUDE.md（プロジェクトメモリ）

## Stack
- プロダクト名: Dify on Azure（Dify を Azure VM で運用する LLM アプリ基盤 + 継続的 LLMOps 評価）
- デプロイ対象: Dify（OSS の LLM アプリ開発プラットフォーム）
- デプロイ方式: Dify 公式 `docker/docker-compose.yaml` を VM 上で起動（アップグレードは公式手順に追従）
- 構成サービス（compose）: `api` / `worker`(Celery) / `web`(Next.js) / `nginx` / `db`(PostgreSQL) / `redis` / `weaviate`（ベクタ DB 既定）/ `sandbox` / `ssrf_proxy`

### インフラ（Azure）
- IaC: **Bicep**（`az deployment group create` で適用、ステートレス）
- ホスト: Azure VM（Ubuntu 22.04 LTS / Linux）+ Managed Disk
- ネットワーク: VNet / Subnet / NSG / Public IP（または Bastion）
- TLS: Nginx + Let's Encrypt(certbot)、ドメインは Azure DNS
- シークレット: Azure Key Vault（`.env` への注入）
- コンテナ実行基盤: Docker / Docker Compose

### LLM プロバイダー
- 主: **Azure OpenAI**（Dify のモデルプロバイダー設定で接続）
- 評価用デプロイ（LLM-as-judge 用）を本番モデルと別枠で確保

### LLMOps（継続的な評価・観測）
- 観測・データ基盤: **Langfuse**（Dify に接続し本番トレース収集・データセット管理・実験記録・ダッシュボード）
- 評価メトリクス: **Ragas**（faithfulness / answer relevancy / context precision / context recall）— Langfuse の scorer として統合
- 評価実行環境: Python 3.12（`uv` で依存管理）+ `pytest`
- （任意）PR ゲート用の高速オフライン回帰: promptfoo を CI に追加

### CI/CD・運用
- CI/CD: GitHub Actions（Bicep の lint / what-if、評価ジョブの定期・PR 実行）
- 言語: Bicep（インフラ）/ シェル（デプロイ・運用スクリプト）/ Python（評価）

## Architecture

3 つのレイヤーで構成する。

### 1. インフラ層（Azure / Bicep）
- Bicep テンプレート（`infra/`）で Azure リソースを宣言的に管理し、`az deployment group create` で適用する。
- 主なリソース: Resource Group / VM（Ubuntu LTS）+ Managed Disk / VNet・Subnet・NSG / Public IP（または Bastion）/ Key Vault。
- VM 起動時の初期化（Docker インストール、リポジトリ取得、`.env` 注入）は cloud-init またはプロビジョニングスクリプトで行う。
- シークレットは Key Vault に集約し、デプロイ時に `.env` へ展開する（リポジトリにはコミットしない）。

### 2. アプリ層（Dify / docker compose）
- VM 上で Dify 公式 `docker compose` を起動。`web`(Next.js) / `api`(Flask) / `worker`(Celery) / `db`(PostgreSQL) / `redis` / `weaviate` / `sandbox` / `ssrf_proxy` / `nginx` が協調動作する。
- 外部公開は `nginx` がリバースプロキシ兼 TLS 終端（Let's Encrypt）として担う。
- LLM 推論は **Azure OpenAI** を Dify のモデルプロバイダーとして接続。本番用と評価(LLM-as-judge)用でデプロイを分ける。
- アップグレードは Dify の公式手順に追従（`docker compose pull` → `up -d`）。独自改変は最小限に留める。

### 3. LLMOps 層（観測・評価）
- **Langfuse**: Dify に接続して本番トレースを収集。実トラフィックから評価用データセットを構築し、実験・スコアを記録・可視化する。
- **Ragas**: faithfulness / answer relevancy / context precision / context recall 等の RAG 品質メトリクスを算出し、Langfuse の scorer として連携する。
- 評価ジョブは Python（`evals/`）で実装し、`pytest` から実行。CI（GitHub Actions）で PR 時・定期的に回し、品質の回帰を検知する。

```
[利用者] → nginx(TLS) → Dify(web/api/worker) → Azure OpenAI
                              │                    （RAG: weaviate）
                              └─ トレース ─→ Langfuse ─ scorer ─→ Ragas
[開発者] → Bicep → Azure(VM) → docker compose（上記スタック）
```

## Commands

```bash
# --- Azure インフラ（Bicep, サブスクリプションスコープ: RG ごと作成） ---
az deployment sub what-if -l japaneast -f infra/main.bicep -p infra/main.bicepparam   # 適用前の差分確認
az deployment sub create  -l japaneast -f infra/main.bicep -p infra/main.bicepparam   # RG + VM/VNet/NSG 等をデプロイ

# --- Dify（VM 上で公式 docker compose） ---
docker compose up -d        # 起動（バックグラウンド）
docker compose ps           # 稼働状況の確認
docker compose logs -f api  # api サービスのログ追従
docker compose pull && docker compose up -d   # イメージ更新→再起動（アップグレード）
docker compose down         # 停止・コンテナ削除

# --- LLMOps 評価（Python 3.12 / uv / pytest） ---
uv sync                     # 評価環境の依存解決
uv run pytest               # Ragas メトリクスによる評価テストを実行
```

## Testing

「インフラの妥当性検証」と「LLM 出力品質の継続評価」の 2 系統を持つ。

### インフラ検証
- `az deployment group what-if` で適用前に差分を確認し、意図しない変更を防ぐ。
- Bicep は `az bicep lint` / `bicep build` で構文・型を検証。CI で PR ごとに実行する。
- デプロイ後はスモークテスト（`docker compose ps` で全サービス healthy か、`/` への HTTP 応答確認）を行う。

### LLM 品質評価（LLMOps）
- 評価コードは `evals/` に置き、`uv run pytest` で実行する。
- **データセット**: Langfuse 上で管理（本番トレースから抽出した質問・期待挙動）。固定の回帰用セットと、本番由来の最新セットを併用する。
- **メトリクス**: Ragas（faithfulness / answer relevancy / context precision / context recall）。閾値を設け、下回ったら fail させて回帰を検知する。
- **判定の安定化**: Ragas は LLM-as-judge のためばらつきが出る。評価用 Azure OpenAI デプロイは temperature を固定し、必要に応じて複数回実行の平均を取る。
- **CI 連携**: GitHub Actions で PR 時（軽量セット）と定期実行（フルセット）に分け、結果を Langfuse に記録して推移を追う。
- （任意）PR ゲート用の高速オフライン回帰が必要なら promptfoo を追加し、LLM コストをかけずに決定的なチェックを行う。

## 注意事項
- 曖昧な指示や方針が未確定のタスクはPlan モードで実行する
- セキュリティを考慮したコーディング（入力バリデーション、エラー情報の過剰露出防止など）
- 設計変更時は対応する図表も同時に更新
- 図表とコードの乖離を防ぐ
- 図表は必要最小限に留め、メンテナンスコストを抑える
