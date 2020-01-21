resource "azurerm_resource_group" "example" {
  name     = "${var.prefix}-k8s-resources"
  location = "${var.location}"
}

resource "azurerm_virtual_network" "example" {
  name                = "${var.prefix}-network"
  address_space       = ["10.139.0.0/16"]
  location            = "${azurerm_resource_group.example.location}"
  resource_group_name = "${azurerm_resource_group.example.name}"
}

resource "azurerm_subnet" "internal" {
  name                 = "${var.prefix}-subnet-internal"
  resource_group_name  = "${azurerm_resource_group.example.name}"
  virtual_network_name = "${azurerm_virtual_network.example.name}"
  address_prefix       = "10.139.1.0/24"
}

resource "azurerm_subnet" "k8s-internal" {
  name                 = "${var.prefix}-k8s-subnet-internal"
  resource_group_name  = "${azurerm_resource_group.example.name}"
  virtual_network_name = "${azurerm_virtual_network.example.name}"
  address_prefix       = "10.139.11.0/24"
}

resource "azurerm_public_ip" "example" {
  name                         = "${var.prefix}-example"
  domain_name_label            = "${var.prefix}-example"
  location                     = "${var.location}"
  resource_group_name          = "${azurerm_resource_group.example.name}"
  public_ip_address_allocation = "static"
}

resource "azurerm_network_interface" "example" {
  name                = "${var.prefix}-nic"
  location            = "${azurerm_resource_group.example.location}"
  resource_group_name = "${azurerm_resource_group.example.name}"

  ip_configuration {
    name                          = "testconfiguration1"
    subnet_id                     = "${azurerm_subnet.internal.id}"
    public_ip_address_id          = "${azurerm_public_ip.example.id}"
    private_ip_address_allocation = "Dynamic"
  }
}

resource "azurerm_virtual_machine" "example" {
  name                  = "${var.prefix}-vm"
  location              = "${azurerm_resource_group.example.location}"
  resource_group_name   = "${azurerm_resource_group.example.name}"
  network_interface_ids = ["${azurerm_network_interface.example.id}"]
  vm_size               = "Standard_DS1_v2"

  # Uncomment this line to delete the OS disk automatically when deleting the VM
  delete_os_disk_on_termination = true


  # Uncomment this line to delete the data disks automatically when deleting the VM
  delete_data_disks_on_termination = true

  storage_image_reference {
    publisher = "Canonical"
    offer     = "UbuntuServer"
    sku       = "16.04-LTS"
    version   = "latest"
  }

  storage_os_disk {
    name              = "myosdisk1"
    caching           = "ReadWrite"
    create_option     = "FromImage"
    managed_disk_type = "Standard_LRS"
  }

  os_profile {
    computer_name  = "${var.prefix}-vm"
    admin_username = "${var.username}"
    admin_password = "${var.password}"
  }
  os_profile_linux_config {
    disable_password_authentication = false
  }
}


resource "azurerm_kubernetes_cluster" "example" {
  name                = "${var.prefix}-k8s"
  location            = "${azurerm_resource_group.example.location}"
  resource_group_name = "${azurerm_resource_group.example.name}"
  dns_prefix          = "${var.prefix}-k8s"

  agent_pool_profile {
    name            = "default"
    count           = 1
    vm_size         = "Standard_D1_v2"
    os_type         = "Linux"
    os_disk_size_gb = 30
    vnet_subnet_id  = "${azurerm_subnet.k8s-internal.id}"
  }

  network_profile {
      network_plugin = "azure"
      docker_bridge_cidr = "172.17.0.1/16"
      service_cidr       = "10.0.0.0/16"
      // An address in the service CIDR
      dns_service_ip     = "10.0.0.10"
  }

  service_principal {
    client_id     = "${var.kubernetes_client_id}"
    client_secret = "${var.kubernetes_client_secret}"
  }

  tags = {
    Environment = "Production"
  }
}