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

resource "azurerm_subnet" "snet_app" {
  name                 = "app"
  resource_group_name  = azurerm_resource_group.rg.name
  virtual_network_name = azurerm_virtual_network.vnet.name
  address_prefixes     = ["10.10.1.0/24"]
}

resource "azurerm_subnet" "snet_db" {
  name                 = "db"
  resource_group_name  = azurerm_resource_group.rg.name
  virtual_network_name = azurerm_virtual_network.vnet.name
  address_prefixes     = ["10.10.2.0/24"]
}

resource "azurerm_storage_account" "st" {
  name                          = "st${var.project}${var.env}001"
  resource_group_name           = azurerm_resource_group.rg.name
  location                      = azurerm_resource_group.rg.location
  account_tier                  = "Standard"
  account_replication_type      = "LRS"
  public_network_access_enabled = true
  tags                          = var.tags
}

resource "azurerm_service_plan" "asp" {
  name                = "${var.project}-${var.env}-asp"
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location
  os_type             = "Linux"
  sku_name            = "B1"
}

resource "azurerm_postgresql_flexible_server" "pg" {
  name                          = "${var.project}-${var.env}-pg"
  resource_group_name           = azurerm_resource_group.rg.name
  location                      = azurerm_resource_group.rg.location
  version                       = "14"
  sku_name                      = "B_Standard_B1ms"
  storage_mb                    = 32768
  administrator_login           = var.postgres_admin_user
  administrator_password        = var.postgres_admin_password
  public_network_access_enabled = true
  backup_retention_days         = 7
  tags                          = var.tags
}

resource "azurerm_postgresql_flexible_server_firewall_rule" "rules" {
  for_each = var.pg_firewall_rules

  name             = each.key
  server_id        = azurerm_postgresql_flexible_server.pg.id
  start_ip_address = each.value.start
  end_ip_address   = each.value.end
}

resource "azurerm_linux_web_app" "apps" {
  for_each = var.webapps

  name                = "${var.project}-${var.env}-${each.key}"
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location
  service_plan_id     = azurerm_service_plan.asp.id

  https_only = each.value.https_only

  virtual_network_subnet_id = azurerm_subnet.snet_app.id

  site_config {
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
