resource "azurerm_resource_group" "rg" {
  name     = "${var.project}-${var.env}-rg"
  location = var.location
}

resource "azurerm_virtual_network" "vnet" {
  name                = "${var.project}-${var.env}-vnet"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  address_space       = ["10.10.0.0/16"]
  tags                = var.tags
}

# Web App用のVNet統合サブネット
resource "azurerm_subnet" "snet_app" {
  name                 = "app"
  resource_group_name  = azurerm_resource_group.rg.name
  virtual_network_name = azurerm_virtual_network.vnet.name
  address_prefixes     = ["10.10.1.0/24"]

  delegation {
    name = "webapp-delegation"
    service_delegation {
      name    = "Microsoft.Web/serverFarms"
      actions = ["Microsoft.Network/virtualNetworks/subnets/action"]
    }
  }
}

# PostgreSQL用のVNetインジェクションサブネット
resource "azurerm_subnet" "snet_db" {
  name                 = "db"
  resource_group_name  = azurerm_resource_group.rg.name
  virtual_network_name = azurerm_virtual_network.vnet.name
  address_prefixes     = ["10.10.2.0/24"]

  delegation {
    name = "pg-delegation"
    service_delegation {
      name    = "Microsoft.DBforPostgreSQL/flexibleServers"
      actions = ["Microsoft.Network/virtualNetworks/subnets/join/action"]
    }
  }
}

# プライベートエンドポイント（Storage用）のサブネット
resource "azurerm_subnet" "snet_pe" {
  name                 = "pe"
  resource_group_name  = azurerm_resource_group.rg.name
  virtual_network_name = azurerm_virtual_network.vnet.name
  address_prefixes     = ["10.10.3.0/24"]
}

# PostgreSQL用 プライベートDNSゾーン
resource "azurerm_private_dns_zone" "dns_pg" {
  name                = "${var.project}-${var.env}.postgres.database.azure.com"
  resource_group_name = azurerm_resource_group.rg.name
}

resource "azurerm_private_dns_zone_virtual_network_link" "dns_pg_link" {
  name                  = "pg-vnet-link"
  private_dns_zone_name = azurerm_private_dns_zone.dns_pg.name
  virtual_network_id    = azurerm_virtual_network.vnet.id
  resource_group_name   = azurerm_resource_group.rg.name
}

# Storage Account用 プライベートDNSゾーン
resource "azurerm_private_dns_zone" "dns_blob" {
  name                = "privatelink.blob.core.windows.net"
  resource_group_name = azurerm_resource_group.rg.name
}

resource "azurerm_private_dns_zone_virtual_network_link" "dns_blob_link" {
  name                  = "blob-vnet-link"
  private_dns_zone_name = azurerm_private_dns_zone.dns_blob.name
  virtual_network_id    = azurerm_virtual_network.vnet.id
  resource_group_name   = azurerm_resource_group.rg.name
}

resource "azurerm_storage_account" "st" {
  # storage account 名は小文字英数字のみ・24文字以内という Azure の制約があるため、
  # project の表示用の値（大文字・ハイフン可）とは別に、名前生成専用の値を作る。
  name                     = "st${local.storage_safe_project}${var.env}001"
  resource_group_name      = azurerm_resource_group.rg.name
  location                 = azurerm_resource_group.rg.location
  account_tier             = "Standard"
  account_replication_type = "LRS"
  min_tls_version          = "TLS1_2"

  # アクセスキーでの認証を無効化し、Azure AD (RBAC) 認証のみを許可する。
  # provider の storage_use_azuread と合わせて、Storage への認証経路を Azure AD に統一する。
  shared_access_key_enabled = false

  # 1. ネットワーク・セキュリティの強化: ストレージアカウントのパブリックネットワークアクセスを無効化（または制限）。
  public_network_access_enabled = false
  tags                          = var.tags
}

# Storage Accountのプライベートエンドポイント
resource "azurerm_private_endpoint" "pe_st" {
  name                = "${var.project}-${var.env}-st-pe"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  subnet_id           = azurerm_subnet.snet_pe.id

  private_service_connection {
    name                           = "st-privatelink"
    private_connection_resource_id = azurerm_storage_account.st.id
    subresource_names              = ["blob"]
    is_manual_connection           = false
  }

  private_dns_zone_group {
    name                 = "blob-dns-zone-group"
    private_dns_zone_ids = [azurerm_private_dns_zone.dns_blob.id]
  }
}

resource "azurerm_service_plan" "asp" {
  name                = "${var.project}-${var.env}-asp"
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location
  os_type             = "Linux"
  sku_name            = "B1"
}

# 1. ネットワーク・セキュリティの強化: 不適切なファイアウォールルール（全開放 0.0.0.0/0）の削除。
# ※ 以前記述されていた azurerm_postgresql_flexible_server_firewall_rule は削除しました。

resource "azurerm_postgresql_flexible_server" "pg" {
  name                   = "${var.project}-${var.env}-pg"
  resource_group_name    = azurerm_resource_group.rg.name
  location               = azurerm_resource_group.rg.location
  version                = "14"
  sku_name               = "B_Standard_B1ms"
  storage_mb             = 32768
  administrator_login    = var.postgres_admin_user
  administrator_password = var.postgres_admin_password
  backup_retention_days  = 7

  # 1. ネットワーク・セキュリティの強化: PostgreSQL Flexible Server のパブリックネットワークアクセスを無効化し、VNet統合（またはプライベートエンドポイント）を適用。
  public_network_access_enabled = false
  delegated_subnet_id           = azurerm_subnet.snet_db.id
  private_dns_zone_id           = azurerm_private_dns_zone.dns_pg.id

  tags       = var.tags
  depends_on = [azurerm_private_dns_zone_virtual_network_link.dns_pg_link]
}

resource "azurerm_linux_web_app" "apps" {
  for_each            = var.webapps
  name                = "${var.project}-${var.env}-${each.key}"
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location
  service_plan_id     = azurerm_service_plan.asp.id
  https_only          = each.value.https_only

  virtual_network_subnet_id = azurerm_subnet.snet_app.id

  site_config {
    # 2. Webアプリ・App Serviceの可用性改善: App Service の always_on を true に変更し、コールドスタートや予期せぬレイテンシを防止。
    # ※ 実際の true 値は variables.tf 側で定義し、ここで展開しています。
    always_on = each.value.always_on
    application_stack {
      node_version = each.value.node_version
    }
  }

  app_settings = {
    ENV                     = var.env
    APP_NAME                = each.key
    POSTGRES_HOST           = azurerm_postgresql_flexible_server.pg.fqdn
    POSTGRES_ADMIN_USER     = var.postgres_admin_user
    POSTGRES_ADMIN_PASSWORD = var.postgres_admin_password
  }

  tags = var.tags
}