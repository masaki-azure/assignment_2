variable "project" {
  description = "Project name"
  type        = string
  default     = "Health-App"
}

locals {
  # storage account 名は小文字英数字のみ・24文字以内という Azure の制約があるため、
  # project の表示用の値（大文字・ハイフン可）とは別に、名前生成専用の値を作る。
  storage_safe_project = lower(replace(var.project, "/[^a-z0-9]/", ""))
}

variable "env" {
  description = "Environment name"
  type        = string
  default     = "stg"
}

variable "location" {
  description = "Azure region"
  type        = string
  default     = "japaneast"
}

variable "tags" {
  description = "Common tags for resources"
  type        = map(string)
  default = {
    owner = "infrastructure-team"
  }
}

# 3. 機密情報の保護（ハードコードの排除） postgres_admin_user,postgres_admin_password
# - `variables.tf` のデフォルト値から推測しやすいパスワードや機密情報のハードコードを削除。
# TODO: App Service の app_settings に渡る DB パスワードを、Key Vault 参照に切り替える
#   （現状は sensitive = true による出力マスクのみで、構成画面には平文で残る）
variable "postgres_admin_user" {
  description = "PostgreSQL Administrator Username"
  type        = string
  sensitive   = true
}

variable "postgres_admin_password" {
  description = "PostgreSQL Administrator Password"
  type        = string
  sensitive   = true
}

variable "webapps" {
  description = "Web App configurations"
  type = map(object({
    node_version = string
    always_on    = bool
    https_only   = bool
  }))
  default = {
    api = {
      node_version = "20-lts"
      # 2. Webアプリ・App Serviceの可用性改善: App Service の always_on を true に変更
      always_on  = true
      https_only = true
    }
    admin = {
      node_version = "20-lts"
      # 2. Webアプリ・App Serviceの可用性改善: App Service の always_on を true に変更
      always_on  = true
      https_only = true
    }
  }
}