# タスク: Terraform State管理基盤の構築(S3ネイティブLock + GitHub Actions OIDC)

## 目的

Terraform Cloudを使わず、AWS S3のネイティブLock機能とGitHub Actions(OIDC認証)でTerraformのstate管理とCI/CDを構築する。

## 前提条件

- Terraform: v1.10以降
- AWSアカウントへのadmin権限(初期構築時のみ)
- GitHubリポジトリ: `<ORG>/<REPO>` (実装時に確認すること)
- AWSリージョン: `ap-northeast-1`
- 環境: `prod`, `stg`, `dev` の3環境を想定
- Terraform のベストプラクティスに従う

## ディレクトリ構成

以下の構成で作成すること。

```
.
├── .github/
│   └── workflows/
│       └── terraform.yml
├── bootstrap/                 # 初期構築用(state管理リソース自身を作る)
│   ├── main.tf
│   ├── variables.tf
│   ├── outputs.tf
│   └── README.md
└── terraform/
    ├── environments/
    │   ├── prod/
    │   │   ├── backend.tf
    │   │   ├── main.tf
    │   │   ├── variables.tf
    │   │   └── terraform.tfvars
    │   ├── stg/
    │   └── dev/
    └── modules/               # 共通モジュール(必要に応じて)
```

## 実装タスク

### Task 1: bootstrap/ の作成

state管理に必要なAWSリソース自身を管理するTerraformコード。
**このディレクトリのstateだけはローカル管理**(鶏と卵問題のため)。

作成するリソース:

1. **S3バケット** (tfstate格納用)
   - バケット名: `<PROJECT_NAME>-tfstate-<AWS_ACCOUNT_ID>` (ユーザに確認)
   - バージョニング: 有効
   - サーバーサイド暗号化: SSE-S3 (AES256)
   - パブリックアクセスブロック: 全て有効
   - ライフサイクルルール: 非現行バージョンは90日後削除

2. **GitHub OIDC Provider**
   - URL: `https://token.actions.githubusercontent.com`
   - audience: `sts.amazonaws.com`

3. **IAMロール** `github-actions-terraform`
   - GitHub OIDCによるAssumeRole
   - `sub`条件で対象リポジトリを制限: `repo:<ORG>/<REPO>:*`
   - 環境ブランチごとに権限を分けたい場合は、`environment`条件も活用

4. **IAMポリシー**: S3とAWSリソース操作権限
   - tfstate用S3バケットへの読み書き権限
   - `.tflock`ファイル操作権限
   - 実リソース管理用の権限(初期はPowerUserAccessでも可、後で最小化)

`bootstrap/README.md` に以下を記載:

- 初回実行手順(`terraform init` → `apply`)
- このstateをローカル管理する理由
- 作成されるリソースの一覧
- 削除時の注意事項

### Task 2: terraform/environments/prod/ の作成

#### backend.tf

```hcl
terraform {
  required_version = ">= 1.10"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  backend "s3" {
    bucket       = "<bootstrap で作成したバケット名>"
    key          = "prod/terraform.tfstate"
    region       = "ap-northeast-1"
    encrypt      = true
    use_lockfile = true
  }
}

provider "aws" {
  region = var.aws_region
}
```

#### variables.tf

- `aws_region` (default: `ap-northeast-1`)
- `environment` (default: `prod`)
- `project_name` (ユーザに確認)

#### main.tf

- 動作確認用に最小限のリソース(例: タグ確認用のS3バケット1つ)を定義
- 本格的なリソースは別タスクで追加する想定

#### terraform.tfvars

- 環境固有の値を記述

**stg/, dev/ も同じ構造で作成**(`key`と`environment`のみ変更)。

### Task 3: GitHub Actionsワークフローの作成

`.github/workflows/terraform.yml`

要件:

- **トリガー**:
  - PR(`terraform/**` の変更) → `plan` のみ実行
  - `main`へのpush → `plan` + `apply` 実行
  - `workflow_dispatch` で環境を選択して手動実行可能
- **マトリクス**: `prod`, `stg`, `dev` の3環境を扱えるようにする
- **権限**:
  - `id-token: write` (OIDC)
  - `contents: read`
  - `pull-requests: write` (PRコメント用)
- **ステップ**:
  1. `actions/checkout@v4`
  2. `aws-actions/configure-aws-credentials@v4` でOIDC認証
  3. `hashicorp/setup-terraform@v3` (v1.10以降)
  4. `terraform fmt -check`
  5. `terraform init`
  6. `terraform validate`
  7. `terraform plan -no-color -out=tfplan`
  8. PR時: planの結果をPRコメントに投稿
  9. `main` push時: `terraform apply -auto-approve` (要 environment承認)
- **環境保護**: `production` 環境にはGitHub Environmentsで手動承認を設定する旨をREADMEに記載

### Task 4: ルートREADMEの作成

`README.md` に以下を記載:

1. このリポジトリの目的
2. ディレクトリ構成の説明
3. 初回セットアップ手順
   - bootstrap実行
   - GitHub SecretsまたはVariablesに必要な値を設定(AWS Account IDなど)
   - GitHub Environmentsの設定方法
4. 日常的な開発フロー
   - ブランチ作成 → PR → plan確認 → マージ → apply
5. トラブルシューティング
   - lock解除方法 (`terraform force-unlock`)
   - state破損時のリカバリ手順(S3バージョニングからの復旧)
6. 命名規則・タグ規約

### Task 5: .gitignore の作成

最低限以下を含めること:

- `.terraform/`
- `*.tfstate`, `*.tfstate.backup`
- `*.tfvars` のうち機密を含むもの (`*.auto.tfvars` は許可するなど方針を明示)
- `tfplan`
- `.terraform.lock.hcl` は**コミット対象**にする(明示的に除外しない)

## 守ってほしい原則

1. **シークレットをコードに含めない** - すべてGitHub SecretsまたはAWS Secrets Manager経由
2. **最小権限の原則** - IAMポリシーは可能な限り絞る。初期はPowerUserAccessでも可だが、READMEに「後で最小化すること」と明記
3. **環境ごとに明確に分離** - state key、tfvars、IAMロールを環境ごとに分けることを検討
4. **冪等性** - 何度実行しても同じ結果になること
5. **ドキュメント駆動** - 各ディレクトリにREADMEを置き、新規参加者が迷わないようにする

## 確認してほしいこと(実装前に質問)

以下はユーザに確認してから実装を開始すること:

1. プロジェクト名(リソース命名で使用)
2. AWSアカウントID
3. GitHubのOrganization名とリポジトリ名
4. 環境は `prod/stg/dev` の3つでよいか
5. tfstate保管用S3バケットを別アカウント(管理アカウント)に置くか、同一アカウントでよいか
6. IAMロールの初期権限はPowerUserAccessでよいか、それとも最初から絞るか

## 完了条件

- [ ] bootstrapを `terraform apply` してエラーなく完了する
- [ ] `terraform/environments/prod` で `terraform init` がS3 backendを認識して成功する
- [ ] `terraform plan` 実行時にS3上に `.tflock` ファイルが作成され、終了時に削除される
- [ ] PRを作成すると、GitHub Actionsがplanを実行し結果がPRコメントに投稿される
- [ ] mainマージ後に承認を経てapplyが実行される
- [ ] 各READMEが整備されている

## 参考情報

- Terraform S3 backend (native locking): <https://developer.hashicorp.com/terraform/language/backend/s3>
- GitHub OIDC for AWS: <https://docs.github.com/en/actions/deployment/security-hardening-your-deployments/configuring-openid-connect-in-amazon-web-services>

## 注意事項

- bootstrapを実行する人物のAWSクレデンシャルは、初期構築時のみ必要。以降はOIDC経由で完結する
- S3バケットは一度作ると名前変更不可。慎重に命名すること
- `use_lockfile = true` はTerraform v1.10以降必須。それ未満のバージョンを使う環境がないか事前に確認すること
