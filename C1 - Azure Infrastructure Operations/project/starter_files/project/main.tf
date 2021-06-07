terraform {
  required_providers {
    azurerm = {
      source = "hashicorp/azurerm"
      version = "2.62.0"
    }
  }
}


provider "azurerm" {
  features {}
}

resource "azurerm_resource_group" "main" {
  name     = "${var.prefix}-rg"
  location = var.location
}

resource "azurerm_virtual_network" "main" {
  name                = "${var.prefix}-network"
  address_space       = ["10.0.0.0/16"]
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name

  tags = {
    "project-rg" = "virtual_network"
  }
}

resource "azurerm_subnet" "internal" {
  name                 = "internal"
  resource_group_name  = azurerm_resource_group.main.name
  virtual_network_name = azurerm_virtual_network.main.name
  address_prefixes     = ["10.0.2.0/24"]

  tags = {
    "project-rg" = "subnet"
  }
}

resource "azurerm_network_interface" "main" {
  name                = "${var.prefix}-nic"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location


  ip_configuration {
    name                          = "internal"
    subnet_id                     = azurerm_subnet.internal.id
    private_ip_address_allocation = "Dynamic"
  }

  tags = {
    "project-rg" = "NIC"
  }
}

resource "azurerm_public_ip" "main" {
  name                = "PublicIPForLB"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  allocation_method   = "Dynamic"

  tags = {
    "project-rg" = "public_ip"
  }
}

resource "azurerm_lb" "main" {
  name                = "loadbalancer"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name

  frontend_ip_configuration {
    name                 = "PublicIPAddress"
    public_ip_address_id = azurerm_public_ip.main.id
  }

  tags = {
    "project-rg" = "loadbalancer"
  }
}

resource "azurerm_lb_backend_address_pool" "main" {
  loadbalancer_id = azurerm_lb.main.id
  name            = "BackEndAddressPool"

  tags = {
    "project-rg" = "backendAddressPool"
  }
}

resource "azurerm_lb_backend_address_pool_address" "main" {
  name                    = "backend_address_pool_address"
  backend_address_pool_id = azurerm_lb_backend_address_pool.main.id
  virtual_network_id      = azurerm_virtual_network.main.id
  ip_address              = "10.0.0.1"

  tags = {
    "project-rg" = "LB_backendAddressPoolAddress"
  }
}


resource "azurerm_network_interface_backend_address_pool_association" "main" {
  network_interface_id    = azurerm_network_interface.main.id
  ip_configuration_name   = "internal"
  backend_address_pool_id = azurerm_lb_backend_address_pool.main.id

  tags = {
    "project-rg" = "NI_backendAddressPoolAddress"
  }
}

resource "azurerm_availability_set" "main" {
  name                = "availability-set"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name

  tags = {
    "project-rg" = "availabilitySet"
  }
}

# we assume that this Custom Image already exists
data "azurerm_image" "main" {
  name                = "${var.custom_image_name}"
  resource_group_name = azurerm_resource_group.main.name

}

resource "azurerm_virtual_machine" "main" {
  count = var.counter
  name                  = "${var.prefix}-vm${count.index}"
  location              = azurerm_resource_group.main.location
  resource_group_name   = azurerm_resource_group.main.name
  network_interface_ids = ["${azurerm_network_interface.main.id}"]
  vm_size               = "Standard_F2"

  # This means the OS Disk will be deleted when Terraform destroys the Virtual Machine
  # NOTE: This may not be optimal in all cases.
  delete_os_disk_on_termination = true

  storage_image_reference {
    id = "${data.azurerm_image.main.id}"
  }

  storage_os_disk {
    name              = "osdisk"
    caching           = "ReadWrite"
    create_option     = "FromImage"
    managed_disk_type = "Standard_LRS"
  }

  os_profile {
    computer_name  = "hostname"
    admin_username = "testadmin"
    admin_password = "Password1234!"
  }

  os_profile_linux_config {
    disable_password_authentication = false
  }

  tags = {
    "project-rg" = "virtual_machine"
  }
}
