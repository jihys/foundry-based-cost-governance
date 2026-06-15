variable "subscription_id" {
  type        = string
  description = "Azure Subscription ID for the management/unified dashboard"
}

variable "location" {
  type        = string
  default     = "eastus"
  description = "Location for the unified dashboard resource group and workbook"
}

variable "team_workspaces" {
  type        = map(string)
  description = "Map of team_name to Log Analytics workspace ARM resource ID"
}
