# -----------------------------------------------------------------------------
# Locals
# -----------------------------------------------------------------------------

locals {
  model_deployments = flatten([
    for region, models in var.regions : [
      for model in models : {
        key      = "${region}-${model.name}"
        region   = region
        name     = model.name
        model    = model.model
        version  = model.version
        sku_name = model.sku_name
        capacity = model.capacity
      }
    ]
  ])

  model_deployment_map = {
    for md in local.model_deployments : md.key => md
  }

  workbook_name = format(
    "%s-%s-%s-%s-%s",
    substr(md5("workbook-${var.team_name}"), 0, 8),
    substr(md5("workbook-${var.team_name}"), 8, 4),
    substr(md5("workbook-${var.team_name}"), 12, 4),
    substr(md5("workbook-${var.team_name}"), 16, 4),
    substr(md5("workbook-${var.team_name}"), 20, 12)
  )
}

# -----------------------------------------------------------------------------
# Data Sources
# -----------------------------------------------------------------------------

data "azurerm_subscription" "current" {}

# -----------------------------------------------------------------------------
# Resource Group
# -----------------------------------------------------------------------------

resource "azurerm_resource_group" "main" {
  name     = "rg-${var.team_name}-ai-foundry"
  location = var.app_insights_location
}

# -----------------------------------------------------------------------------
# Monitoring — Log Analytics Workspace + Application Insights
# -----------------------------------------------------------------------------

resource "azurerm_log_analytics_workspace" "main" {
  name                = "law-${var.team_name}"
  location            = var.app_insights_location
  resource_group_name = azurerm_resource_group.main.name
  sku                 = "PerGB2018"
  retention_in_days   = 30
}

resource "azurerm_application_insights" "main" {
  name                = "appi-${var.team_name}"
  location            = var.app_insights_location
  resource_group_name = azurerm_resource_group.main.name
  workspace_id        = azurerm_log_analytics_workspace.main.id
  application_type    = "web"
}

# -----------------------------------------------------------------------------
# Foundry Resources — Azure AI Services (per region)
# -----------------------------------------------------------------------------

resource "azurerm_cognitive_account" "ai" {
  for_each = var.regions

  name                  = "ai-${var.team_name}-${each.key}"
  location              = each.key
  resource_group_name   = azurerm_resource_group.main.name
  kind                  = "AIServices"
  sku_name              = "S0"
  custom_subdomain_name = "ai-${var.team_name}-${each.key}"
}

# -----------------------------------------------------------------------------
# Model Deployments (per model per region)
# -----------------------------------------------------------------------------

resource "azurerm_cognitive_deployment" "model" {
  for_each = local.model_deployment_map

  name                 = each.value.name
  cognitive_account_id = azurerm_cognitive_account.ai[each.value.region].id

  model {
    format  = "OpenAI"
    name    = each.value.model
    version = each.value.version
  }

  sku {
    name     = each.value.sku_name
    capacity = each.value.capacity
  }
}

# -----------------------------------------------------------------------------
# Diagnostic Settings — wire each Foundry Resource → Log Analytics
# -----------------------------------------------------------------------------

resource "azurerm_monitor_diagnostic_setting" "ai" {
  for_each = var.regions

  name                       = "diag-${var.team_name}-${each.key}"
  target_resource_id         = azurerm_cognitive_account.ai[each.key].id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.main.id

  enabled_log {
    category = "RequestResponse"
  }

  enabled_log {
    category = "Audit"
  }

  enabled_log {
    category = "AzureOpenAIRequestUsage"
  }

  enabled_metric {
    category = "AllMetrics"
  }
}

# -----------------------------------------------------------------------------
# Budget Alert
# -----------------------------------------------------------------------------

resource "azurerm_consumption_budget_subscription" "main" {
  name            = "budget-${var.team_name}"
  subscription_id = data.azurerm_subscription.current.id
  amount          = var.monthly_budget_usd
  time_grain      = "Monthly"

  time_period {
    start_date = "2026-06-01T00:00:00Z"
  }

  notification {
    enabled        = true
    threshold      = 80
    operator       = "GreaterThanOrEqualTo"
    threshold_type = "Actual"
    contact_emails = [var.alert_email]
  }

  notification {
    enabled        = true
    threshold      = 100
    operator       = "GreaterThanOrEqualTo"
    threshold_type = "Actual"
    contact_emails = [var.alert_email]
  }

  notification {
    enabled        = true
    threshold      = 100
    operator       = "GreaterThanOrEqualTo"
    threshold_type = "Forecasted"
    contact_emails = [var.alert_email]
  }
}

# -----------------------------------------------------------------------------
# Cost Dashboard Workbook
# -----------------------------------------------------------------------------

resource "azurerm_application_insights_workbook" "cost_dashboard" {
  name                = local.workbook_name
  location            = var.app_insights_location
  resource_group_name = azurerm_resource_group.main.name
  display_name        = "Cost Dashboard - ${var.team_name}"
  source_id           = lower(azurerm_application_insights.main.id)

  data_json = jsonencode({
    version = "Notebook/1.0"
    items = [
      {
        type = 1
        content = {
          json = "# Cost Dashboard — ${var.team_name}\nRequest activity and performance monitoring for Azure AI Services."
        }
        name = "header"
      },
      {
        type = 3
        content = {
          version                 = "KqlItem/1.0"
          query                   = <<-KQL
            AzureDiagnostics
            | where ResourceProvider == "MICROSOFT.COGNITIVESERVICES"
            | where Category == "RequestResponse"
            | extend model_name = tostring(parse_json(properties_s).modelName)
            | summarize
                RequestCount = count(),
                AvgDurationMs = round(avg(DurationMs), 1),
                TotalResponseBytes = sum(toint(parse_json(properties_s).responseLength))
              by bin(TimeGenerated, 1d), model_name
            | order by TimeGenerated desc
          KQL
          size                    = 0
          timeContext             = { durationMs = 2592000000 }
          queryType               = 0
          resourceType            = "microsoft.operationalinsights/workspaces"
          crossComponentResources = [azurerm_log_analytics_workspace.main.id]
          visualization           = "barchart"
          chartSettings = {
            xAxis = "TimeGenerated"
            yAxis = ["RequestCount"]
            group = "model_name"
          }
        }
        name = "request-activity-daily"
      },
      {
        type = 3
        content = {
          version                 = "KqlItem/1.0"
          query                   = <<-KQL
            AzureDiagnostics
            | where ResourceProvider == "MICROSOFT.COGNITIVESERVICES"
            | where Category == "RequestResponse"
            | extend model_name = tostring(parse_json(properties_s).modelName)
            | extend req_len = toint(parse_json(properties_s).requestLength)
            | extend resp_len = toint(parse_json(properties_s).responseLength)
            | summarize
                TotalRequests = count(),
                AvgDurationMs = round(avg(DurationMs), 1),
                TotalRequestBytes = sum(req_len),
                TotalResponseBytes = sum(resp_len)
              by model_name
            | order by TotalRequests desc
          KQL
          size                    = 0
          timeContext             = { durationMs = 2592000000 }
          queryType               = 0
          resourceType            = "microsoft.operationalinsights/workspaces"
          crossComponentResources = [azurerm_log_analytics_workspace.main.id]
          visualization           = "table"
        }
        name = "model-summary"
      },
      {
        type = 3
        content = {
          version                 = "KqlItem/1.0"
          query                   = <<-KQL
            AzureDiagnostics
            | where ResourceProvider == "MICROSOFT.COGNITIVESERVICES"
            | where Category == "RequestResponse"
            | extend model_name = tostring(parse_json(properties_s).modelName)
            | summarize
                AvgDurationMs = round(avg(DurationMs), 1),
                P95DurationMs = round(percentile(DurationMs, 95), 1),
                RequestCount = count()
              by bin(TimeGenerated, 1d), model_name
            | order by TimeGenerated desc
          KQL
          size                    = 0
          timeContext             = { durationMs = 2592000000 }
          queryType               = 0
          resourceType            = "microsoft.operationalinsights/workspaces"
          crossComponentResources = [azurerm_log_analytics_workspace.main.id]
          visualization           = "linechart"
          chartSettings = {
            xAxis = "TimeGenerated"
            yAxis = ["AvgDurationMs"]
            group = "model_name"
          }
        }
        name = "response-time-trend"
      },
      {
        type = 3
        content = {
          version                 = "KqlItem/1.0"
          query                   = <<-KQL
            AzureDiagnostics
            | where ResourceProvider == "MICROSOFT.COGNITIVESERVICES"
            | where Category == "RequestResponse"
            | extend model_name = tostring(parse_json(properties_s).modelName)
            | summarize RequestCount = count() by bin(TimeGenerated, 1d), model_name
            | order by TimeGenerated desc
          KQL
          size                    = 0
          timeContext             = { durationMs = 2592000000 }
          queryType               = 0
          resourceType            = "microsoft.operationalinsights/workspaces"
          crossComponentResources = [azurerm_log_analytics_workspace.main.id]
          visualization           = "barchart"
          chartSettings = {
            xAxis = "TimeGenerated"
            yAxis = ["RequestCount"]
            group = "model_name"
          }
        }
        name = "request-count-daily"
      }
    ]
    fallbackResourceIds = []
  })
}
