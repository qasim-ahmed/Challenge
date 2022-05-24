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

# variable "resourcename" {
#   type = string
#   description = "Please enter the Resource Group Name"
# }

# variable "virtualnetworkname" {
#   type = string
#   description = "Please enter the Virtual Network Name"

# }

# variable "virtualmachinesize" {
#   type = string
#   description = "Please enter the Virtual Machine Size"
# }

# variable "databasetype" {
#   type = string
#   description = "Please enter the database type"
# }

locals {
  location="West Europe"
  password="${random_string.random.result}"
}



resource "random_string" "random" {
  length           = 12
  special          = true
  override_special = "/@£$"
}

resource "azurerm_resource_group" "app_resource" {
    name = $(resourcename)
    location = local.location
  
}

# resource "azurerm_storage_account" "app_storage" {
#   name                     = "app-storage"
#   resource_group_name      = resourcename
#   location                 = local.location
#   account_tier             = "Standard"
#   account_replication_type = "GRS"
#   allow_nested_items_to_be_public = true




# resource "azurerm_storage_container" "app_container" {
#   name                  = "app-container"
#   storage_account_name  = azurerm_storage_account.app_storage.name
#   container_access_type = "public"
# }



# Create virtual network
resource "azurerm_virtual_network" "virtual_network" {
  name                = virtualnetworkname
  address_space       = ["10.0.0.0/16"]
  location            = azurerm_resource_group.app_resource.location
  resource_group_name = azurerm_resource_group.app_resource.name

  tags = {
    environment = "production"
  }
}

# Create subnet
resource "azurerm_subnet" "network_subnet" {
  name                 = "Subnet1"
  resource_group_name  = azurerm_resource_group.app_resource.name
  virtual_network_name = azurerm_virtual_network.virtual_network.name
  address_prefixes     = ["10.0.1.0/24"]
}

# Create public IPs
resource "azurerm_public_ip" "public_ip" {
  name                = "public-ip"
  location            = azurerm_resource_group.app_resource.location
  resource_group_name = azurerm_resource_group.app_resource.name
  allocation_method   = "Dynamic"

  tags = {
    environment = "production"
  }
}

# Create Network Security Group and rule
resource "azurerm_network_security_group" "network_sec_group" {
  name                = "network-security-group"
  location            = azurerm_resource_group.app_resource.location
  resource_group_name = azurerm_resource_group.app_resource.name

  security_rule {
    name                       = "SSH"
    priority                   = 1001
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "22"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  tags = {
    environment = "production"
  }
}

# Create network interface
resource "azurerm_network_interface" "network_interface" {
  name                = "network-interface"
  location            = azurerm_resource_group.app_resource.location
  resource_group_name = azurerm_resource_group.app_resource.name

  ip_configuration {
    name                          = "myNicConfiguration"
    subnet_id                     = azurerm_subnet.network_subnet.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.public_ip.id
  }

  tags = {
    environment = "production"
  }
}

# Connect the security group to the network interface
resource "azurerm_network_interface_security_group_association" "association" {
  network_interface_id      = azurerm_network_interface.network_interface.id
  network_security_group_id = azurerm_network_security_group.network_sec_group.id
}


# Create Linux Virtual Machine
resource "azurerm_linux_virtual_machine" "linux_machine" {
  name                  = "linux-machine"
  location              = azurerm_resource_group.app_resource.location
  resource_group_name   = azurerm_resource_group.app_resource.name
  network_interface_ids = [azurerm_network_interface.network_interface.id]
  size                  =  virtualmachinesize

  os_disk {
    name                 = "myOsDisk"
    caching              = "ReadWrite"
    storage_account_type = "Premium_LRS"
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "UbuntuServer"
    sku       = "18.04-LTS"
    version   = "latest"
  }

  computer_name                   = "myvm"
  admin_username                  = "azureuser"
  admin_password = local.password
  disable_password_authentication = false


  tags = {
    environment = "production"
  }
}





# Creating one sample user once VM is provisioned

resource "azurerm_virtual_machine_extension" "virtual_machine_extensions" {
  name                 = "virtual-machine-extensions"
  virtual_machine_id   = azurerm_linux_virtual_machine.linux_machine.id
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

resource "random_integer" "ri" {
  min = 10000
  max = 99999
}


resource "azurerm_cosmosdb_account" "cosmo_db_account" {
  name = "tfex-cosmos-db-${random_integer.ri.result}"
  location = local.location
  resource_group_name = resourcename
  offer_type = "Standard"
  kind = "GlobalDocumentDB"
  enable_automatic_failover = true
consistency_policy {
    consistency_level = "Session"
  }
  
  geo_location {
    location = "australiasoutheast"
    failover_priority = 1
  }
geo_location {
    location = local.location
    failover_priority = 0
  }
}





resource "azurerm_cosmosdb_sql_database" "sql_database" {
  count = databasetype == "sql" ? 1: 0
  name                = "cosmos-sql-db"
  resource_group_name = "${azurerm_cosmosdb_account.cosmo_db_account.resource_group_name}"
  account_name        = "${azurerm_cosmosdb_account.cosmo_db_account.name}"
  throughput          = 400
}


resource "azurerm_cosmosdb_mongo_database" "mongo_database" {
  count = databasetype == "mongo" ? 1: 0
  name                = "cosmos-mongo-db"
  resource_group_name = "${azurerm_cosmosdb_account.cosmo_db_account.resource_group_name}"
  account_name        = "${azurerm_cosmosdb_account.cosmo_db_account.name}"
  throughput          = 400
}



resource "azurerm_cosmosdb_gremlin_database" "gremlin_database" {
  count = databasetype == "gremlin" ? 1: 0
  name                = "cosmos-gremlin-db"
  resource_group_name = resourcename
  account_name        = "${azurerm_cosmosdb_account.cosmo_db_account.name}"
  throughput          = 400
}


output "databasepass" {
  value = local.password
}

output "dbpwd" {
    value = random_string.random
}

output "databasekey" {
    value = nonsensitive(azurerm_cosmosdb_account.cosmo_db_account.primary_key)
}

output "databaseconnectionstrings" {
    value = nonsensitive(azurerm_cosmosdb_account.cosmo_db_account.connection_strings)
  
}


