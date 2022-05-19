terraform {
  required_providers {
    azurerm = {
      source = "hashicorp/azurerm"
      version = "3.6.0"
    }
  }
}

provider "azurerm" {
  # Configuration options
  subscription_id = "de255c89-79d1-4652-9b7c-81d828c5beaa"
  client_id = "a934dbef-210e-4a65-a9f0-55d4db6b6266"
  client_secret = "fxT8Q~7tZpzGnUXNLNqpxlVzZ6SIDFGubQZy0c5c"
  tenant_id = "4e2772a8-27fa-42a7-b6bb-680785f0b12a"
  features {}
}

variable "resourcename" {
  type = string
  description = "Please enter the Resource Group Name"
}

variable "virtualnetworkname" {
  type = string
  description = "Please enter the Virtual Network Name"

}

variable "virtualmachinesize" {
  type = string
  description = "Please enter the Virtual Machine Size"
}

variable "databasetype" {
  type = string
  description = "Please enter the database type"
}

locals {
  location="North Europe"
  password="${random_string.random.result}"
}

data "azurerm_subnet" "Subnet1" {
    name = "Subnet1"
    virtual_network_name = var.virtualnetworkname
    resource_group_name = var.resourcename
  
}


resource "random_string" "random" {
  length           = 12
  special          = true
  override_special = "/@£$"
}

resource "azurerm_resource_group" "app_resource" {
    name = var.resourcename
    location = local.location
  
}

resource "azurerm_storage_account" "app_storage" {
  name                     = "app-storage"
  resource_group_name      = var.resourcename
  location                 = local.location
  account_tier             = "Standard"
  account_replication_type = "GRS"
  allow_nested_items_to_be_public = true

#   tags = {
#     environment = "staging"
#   }
}


resource "azurerm_storage_container" "app_container" {
  name                  = "app-container"
  storage_account_name  = azurerm_storage_account.app_storage.name
  container_access_type = "public"
}

resource "azurerm_network_security_group" "network_security_group" {
  name                = "network-security-group"
  location            = local.location
  resource_group_name = var.resourcename
}

resource "azurerm_virtual_network" "virtual_network" {
  name                = var.virtualnetworkname
  location            = local.location
  resource_group_name = var.resourcename
  address_space       = ["10.0.0.0/16"]
  dns_servers         = ["10.0.0.4", "10.0.0.5"]

  subnet {
    name           = "Subnet1"
    address_prefix = "10.0.2.0/24"
    security_group = azurerm_network_security_group.network_security_group.id
  }

}


resource "azurerm_network_interface" "network_interface" {
  name                = "network-interface"
  location            = local.location
  resource_group_name = var.resourcename

  ip_configuration {
    name                          = "internal"
    subnet_id                     = data.azurerm_subnet.Subnet1.id
    private_ip_address_allocation = "Dynamic"
  }
}

# Linux Virtual Machine

resource "azurerm_linux_virtual_machine" "linux_virtual_machine" {
  name                = "example-machine"
  resource_group_name = var.resourcename
  location            = local.location
  size                = var.virtualmachinesize
  admin_username      = "myadmin"
  admin_password = local.password
  network_interface_ids = [
    azurerm_network_interface.network_interface.id,
  ]

#   admin_ssh_key {
#     username   = "adminuser"
#     public_key = file("~/.ssh/id_rsa.pub")
#   }

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "UbuntuServer"
    sku       = "16.04-LTS"
    version   = "latest"
  }
}

# Creating one sample user once VM is provisioned

resource "azurerm_virtual_machine_extension" "virtual_machine_extensions" {
  name                 = "virtual-machine-extensions"
  virtual_machine_id   = azurerm_linux_virtual_machine.linux_virtual_machine.id
  publisher            = "Microsoft.Azure.Extensions"
  type                 = "CustomScript"
  type_handler_version = "2.0"

  settings = <<SETTINGS
    {
        "commandToExecute": "useradd -m -p mysamplepassword dummyuser"
    }
SETTINGS

  tags = {
    environment = "Production"
  }
}


resource "azurerm_cosmosdb_account" "cosmo_db_account" {
  name                = "cosmo-db-account"
  location            = local.location
  resource_group_name = var.resourcename
  offer_type          = "Standard"

  enable_automatic_failover = true

  consistency_policy {
    consistency_level       = "BoundedStaleness"
    max_interval_in_seconds = 300
    max_staleness_prefix    = 100000
  }

  geo_location {
    location          = local.location
    failover_priority = 0
  }
}


resource "azurerm_cosmosdb_sql_database" "sql_database" {
  count = var.databasetype == "sql" ? 1: 0
  name                = "cosmos-sql-db"
  resource_group_name = var.resourcename
  account_name        = data.azurerm_cosmosdb_account.cosmo_db_account.name
  throughput          = 400
}


resource "azurerm_cosmosdb_mongo_database" "example" {
  count = var.databasetype == "mongo" ? 1: 0
  name                = "cosmos-mongo-db"
  resource_group_name = var.resourcename
  account_name        = data.azurerm_cosmosdb_account.cosmo_db_account.name
  throughput          = 400
}


resource "azurerm_cosmosdb_gremlin_database" "example" {
  count = var.databasetype == "gremlin" ? 1: 0
  name                = "cosmos-gremlin-db"
  resource_group_name = var.resourcename
  account_name        = data.azurerm_cosmosdb_account.cosmo_db_account.name
  throughput          = 400
}


output "databasepassword" {
  value = local.password
}

output "dbpassword" {
    value = random_string.random
}

output "databasekey" {
    value = azurerm_cosmosdb_account.cosmo_db_account.primary_key
}

output "databaseconnectionstrings" {
    value = azurerm_cosmosdb_account.cosmo_db_account.connection_string
  
}
