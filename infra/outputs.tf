output "team_name" {
  value       = var.team_name
  description = "Team name"
}

output "team_info" {
  value = {
    subscription_id = var.subscription_id
    resource_group  = azurerm_resource_group.main.name
    regions = {
      for region, _ in var.regions : region => {
        endpoint = azurerm_cognitive_account.ai[region].endpoint
        key1     = azurerm_cognitive_account.ai[region].primary_access_key
        key2     = azurerm_cognitive_account.ai[region].secondary_access_key
        model_deployments = [
          for md in local.model_deployments : md.name if md.region == region
        ]
      }
    }
    application_insights_connection_string = azurerm_application_insights.main.connection_string
    application_insights_id                = azurerm_application_insights.main.app_id
  }
  sensitive   = true
  description = "Team resource info: endpoints, keys, model deployments per region (consumed by Key Export)"
}
