# bootstrap

Terraform state 管理に必要な AWS リソース自身を作成する Terraform スタック。

## このディレクトリの state はローカル管理

このスタックは「state を保管する S3 バケット」と「GitHub Actions が AssumeRole する IAM ロール」を作成する。
それらを使うための backend を、それらを作る前に指定することはできない (鶏と卵)。

したがって **bootstrap/ の state はローカル管理** (`terraform.tfstate` がこのディレクトリに保存される)。
一度作成したら原則として再 apply は不要。変更が必要になった場合のみ、ローカルから再実行する。

> `.gitignore` で `*.tfstate` は除外しているため、ローカル state がコミットされる事故は防がれている。
> ただしローカル state の紛失リスクを避けるため、apply 後の `terraform.tfstate` は別途バックアップしておくことを推奨。

## 作成されるリソース

| 種別 | 名前 | 用途 |
|---|---|---|
| S3 Bucket | `learn-tf-tfstate-456788081138` | 各環境の tfstate 格納 (バージョニング有効 / SSE-S3 / Public Block / 非現行版 90 日で削除) |
| IAM OIDC Provider | `token.actions.githubusercontent.com` | **既存リソースを `data` で参照** (AWS アカウント内で 1 つしか作れない共有リソースのため、所有しない設計) |
| IAM Role | `github-actions-terraform` | GitHub Actions が AssumeRole する Terraform 実行用ロール |
| IAM Policy | `github-actions-terraform-tfstate-access` | tfstate バケット + `.tflock` ファイルの読み書き |
| IAM Policy | `github-actions-terraform-managed-resources` | 各環境スタックが管理する実リソース (現状は `learn-tf-sample-*` プレフィックスの S3 のみ) |

IAM ロールの `sub` 条件は `repo:Mo3g4u/terraform-state-s3-github-actions:*` に制限されている。

## 初回実行手順

1. **AWS クレデンシャルを設定**
   ローカルから admin 相当の権限で apply するため、`aws configure` か `AWS_PROFILE` で対象アカウントに接続できる状態にする。

   ```bash
   aws sts get-caller-identity   # Account: 456788081138 であることを確認
   ```

2. **terraform init / plan / apply**

   ```bash
   cd bootstrap/
   terraform init
   terraform plan
   terraform apply
   ```

3. **outputs を控える**
   apply 完了後、以下の出力値を確認し、各環境の `backend.tf` のバケット名と一致していることを確認する。

   ```
   tfstate_bucket_name      = "learn-tf-tfstate-456788081138"
   github_actions_role_arn  = "arn:aws:iam::456788081138:role/github-actions-terraform"
   ```

   GitHub Actions の Variables (または Secrets) に以下を登録する:
   - `AWS_ROLE_ARN` = `github_actions_role_arn`
   - `AWS_ACCOUNT_ID` = `456788081138` (任意)

## 削除時の注意事項

- **tfstate バケットには `lifecycle { prevent_destroy = true }` が設定されている**。
  誤って削除されないように保護されている。本当に削除する場合は、`main.tf` の該当ブロックを削除してから `terraform destroy` する。
- バケット内に各環境の tfstate が残っている状態で destroy すると失敗する。
  事前に全環境を `terraform destroy` してから bootstrap を消すこと。
- **OIDC プロバイダーはこのスタックの管理対象外** (`data` 参照のみ)。bootstrap を destroy しても OIDC Provider は削除されない。他リポジトリと共有しているため、これは意図した挙動。

## IAM 権限について

`github-actions-terraform-managed-resources` ポリシーは **最小権限** で設定されている。
現状の許可範囲:
- `s3:ListAllMyBuckets`, `s3:GetBucketLocation` (plan 用)
- `s3:*` 系の主要アクション (`arn:aws:s3:::learn-tf-sample-*` のみ)

新しいリソース種別 (EC2, RDS, IAM 等) を環境スタックに追加する際は、このポリシーを拡張する必要がある。
拡張は **最小権限を維持** すること (例: `ec2:*` ではなく必要な action と resource を絞る)。
