variable "team_name" {
  type        = string
  description = "Project team name (e.g. catalog, image, search)"
}

variable "subscription_id" {
  type        = string
  description = "Azure Subscription ID for this team"
}

variable "regions" {
  type = map(list(object({
    name     = string
    model    = string
    version  = string
    sku_name = string
    capacity = number
  })))
  description = "Map of Azure region to list of model deployment objects"
}

variable "app_insights_location" {
  type        = string
  default     = "eastus"
  description = "Location for Application Insights and related monitoring resources"
}

variable "monthly_budget_usd" {
  type        = number
  default     = 100
  description = "Monthly budget threshold in USD"
}

variable "alert_email" {
  type        = string
  description = "Email address for budget alert notifications"
}
