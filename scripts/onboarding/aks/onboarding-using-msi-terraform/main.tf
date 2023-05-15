resource "azurerm_resource_group" "rg" {
  name     = var.aks_resource_group_name
  location = var.resource_group_location
}

resource "azurerm_kubernetes_cluster" "k8s" {
  name                = var.cluster_name
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  dns_prefix          = var.dns_prefix

  tags = var.resource_tag_values
  
  default_node_pool {
    name       = "agentpool"
    vm_size    = "Standard_D2_v2"
    node_count = var.agent_count
  }

  identity {
    type = "SystemAssigned"
  }

  oms_agent {
    log_analytics_workspace_id = var.workspace_resource_id
    msi_auth_for_monitoring_enabled = true
  }

  network_profile {
    network_plugin    = "kubenet"
    load_balancer_sku = "standard"
  }
}

resource "azurerm_monitor_data_collection_rule" "dcr" {
  name                = "MSCI-dcr-${var.workspace_region}-${var.cluster_name}"
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location

  destinations {
    log_analytics {
      workspace_resource_id = var.workspace_resource_id
      name                  = "ciworkspace"
    }
  }

  data_flow {
    streams      = ["Microsoft-ContainerInsights-Group-Default"]
    destinations = ["ciworkspace"]
  }

  data_sources {
    extension {
      streams            = ["Microsoft-ContainerInsights-Group-Default"]
      extension_name     = "ContainerInsights"
      extension_json = jsonencode({
        "extensionSettings": {
            "dataCollectionSettings" : {
                "interval": var.data_collection_interval,
                "namespaceFilteringMode": var.namespace_filtering_mode_for_data_collection,
                "namespaces": var.namespaces_for_data_collection
            }
        }
      })
      name = "ContainerInsightsExtension"
    }
  }

  description = "DCR for Azure Monitor Container Insights"
}

resource "azurerm_monitor_data_collection_rule_association" "dcra" {
  name                        = "MSCI-dcra-${var.workspace_region}-${var.cluster_name}"
  target_resource_id          = azurerm_kubernetes_cluster.k8s.id
  data_collection_rule_id     = azurerm_monitor_data_collection_rule.dcr.id
  description                 = "Association of data collection rule. Deleting this association will break the data collection for this AKS Cluster."
}