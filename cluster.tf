resource "azurerm_resource_group" "my-aks-rg" {
  name     = "my-aks-rg"
  location = var.location
}

resource "azurerm_kubernetes_cluster" "my-aks-cluster" {
  name                = "my-aks-cluster"
  location            = azurerm_resource_group.my-aks-rg.location
  resource_group_name = azurerm_resource_group.my-aks-rg.name
  dns_prefix          = "my-aks-cluster"
  kubernetes_version  = var.kubernetes_version

  default_node_pool {
    name            = "default"
    node_count      = 1
    vm_size         = "Standard_E4s_v3"
    type            = "VirtualMachineScaleSets"
    os_disk_size_gb = 250
  }

  service_principal {
    client_id     = var.serviceprincipal_id
    client_secret = var.serviceprincipal_key
  }

  linux_profile {
    admin_username = "my_admin_username"
    ssh_key {
      key_data = var.ssh_key
    }
  }

  network_profile {
    network_plugin    = "kubenet"
    load_balancer_sku = "standard"
  }
}

variable "location" {
  default = "centralus"
}

variable "kubernetes_version" {
  default = "1.24.3"
}

variable "serviceprincipal_id" {
}

variable "serviceprincipal_key" {
}

variable "ssh_key" {
}
