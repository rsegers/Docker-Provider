variable "agent_count" {
  default = 3
}

variable "aks_resource_group_name" {
  type = string
  default = "<ResourceGroup>"
}

variable "resource_group_location" {
  type = string
  default = "<ResourceGroupLocation>"
}

variable "cluster_name" {
  type = string
  default = "<ClusterName>"
}

variable "dns_prefix" {
  default = "k8stest"
}

variable "workspace_resource_id" {
  type = string
  default = "/subscriptions/<SubscriptionId>/resourceGroups/<ResourceGroup>/providers/Microsoft.OperationalInsights/workspaces/<workspaceName>"
}

variable "workspace_region" {
  type = string
  default = "<workspaceRegion>"
}

variable "enable_syslog" {
  type = string
  default = false
}

variable "syslog_levels" {
  type = list(string)
  default = ["Debug", "Info", "Notice", "Warning", "Error", "Critical", "Alert", "Emergency"]
}

variable "syslog_facilities" {
  type = list(string)
  default = ["auth", "authpriv", "cron", "daemon", "mark", "kern", "local0", "local1", "local2", "local3", "local4", "local5", "local6", "local7", "lpr", "mail", "news", "syslog", "user", "uucp"]
}

variable "resource_tag_values" {
  description = "Resource Tag Values"
  type = map(string)
  default = {
    "<existingOrnew-tag-name1>" = "<existingOrnew-tag-value1>"
    "<existingOrnew-tag-name2>" = "<existingOrnew-tag-value2>"
    "<existingOrnew-tag-name3>" = "<existingOrnew-tag-value3>"
  }
}

variable "data_collection_interval" {
  default = "1m"
}

variable "namespace_filtering_mode_for_data_collection" {
  default = "Off"
}

variable "namespaces_for_data_collection" {
  default = ["kube-system", "gatekeeper-system", "azure-arc"]
}
