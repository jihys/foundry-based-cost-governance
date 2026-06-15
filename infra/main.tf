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
          json = "# Cost Dashboard — ${var.team_name}\nToken usage and cost monitoring for Azure AI Services."
        }
        name = "header"
      },
      {
        type = 3
        content = {
          version       = "KqlItem/1.0"
          query         = <<-KQL
            AzureDiagnostics
            | where ResourceProvider == "MICROSOFT.COGNITIVESERVICES"
            | where Category == "AzureOpenAIRequestUsage"
            | extend props = parse_json(properties_s)
            | extend model_name = tostring(props.modelName)
            | extend prompt_tokens = toint(props.promptTokens)
            | extend completion_tokens = toint(props.completionTokens)
            | extend total_tokens = prompt_tokens + completion_tokens
            | summarize
                TotalPromptTokens = sum(prompt_tokens),
                TotalCompletionTokens = sum(completion_tokens),
                TotalTokens = sum(total_tokens),
                Requests = count()
              by bin(TimeGenerated, 1d), model_name
            | order by TimeGenerated desc
          KQL
          size          = 0
          timeContext   = { durationMs = 2592000000 }
          queryType     = 0
          resourceType  = "microsoft.operationalinsights/workspaces"
          visualization = "barchart"
          chartSettings = {
            xAxis = "TimeGenerated"
            yAxis = ["TotalTokens"]
            group = "model_name"
          }
        }
        name = "token-usage-daily"
      },
      {
        type = 3
        content = {
          version       = "KqlItem/1.0"
          query         = <<-KQL
            AzureDiagnostics
            | where ResourceProvider == "MICROSOFT.COGNITIVESERVICES"
            | where Category == "AzureOpenAIRequestUsage"
            | extend props = parse_json(properties_s)
            | extend model_name = tostring(props.modelName)
            | extend prompt_tokens = toint(props.promptTokens)
            | extend completion_tokens = toint(props.completionTokens)
            | extend total_tokens = prompt_tokens + completion_tokens
            | summarize
                PromptTokens = sum(prompt_tokens),
                CompletionTokens = sum(completion_tokens),
                TotalTokens = sum(total_tokens),
                TotalRequests = count()
              by model_name
            | order by TotalTokens desc
          KQL
          size          = 0
          timeContext   = { durationMs = 2592000000 }
          queryType     = 0
          resourceType  = "microsoft.operationalinsights/workspaces"
          visualization = "table"
        }
        name = "token-summary-by-model"
      },
      {
        type = 3
        content = {
          version       = "KqlItem/1.0"
          query         = <<-KQL
            let model_pricing = datatable(model_name: string, input_price_per_1k: real, output_price_per_1k: real) [
                "gpt-4o",                  0.0025,  0.01,
                "gpt-4.1-mini",            0.0004,  0.0016,
                "o3-mini",                 0.0011,  0.0044,
                "text-embedding-3-large",  0.00013, 0.0
            ];
            AzureDiagnostics
            | where ResourceProvider == "MICROSOFT.COGNITIVESERVICES"
            | where Category == "AzureOpenAIRequestUsage"
            | extend props = parse_json(properties_s)
            | extend model_name = tostring(props.modelName)
            | extend prompt_tokens = toint(props.promptTokens)
            | extend completion_tokens = toint(props.completionTokens)
            | lookup kind=leftouter model_pricing on model_name
            | extend input_cost = prompt_tokens / 1000.0 * coalesce(input_price_per_1k, 0.001)
            | extend output_cost = completion_tokens / 1000.0 * coalesce(output_price_per_1k, 0.002)
            | extend total_cost = input_cost + output_cost
            | summarize
                DailyCostUSD = sum(total_cost)
              by bin(TimeGenerated, 1d), model_name
            | order by TimeGenerated desc
          KQL
          size          = 0
          timeContext   = { durationMs = 2592000000 }
          queryType     = 0
          resourceType  = "microsoft.operationalinsights/workspaces"
          visualization = "linechart"
          chartSettings = {
            xAxis = "TimeGenerated"
            yAxis = ["DailyCostUSD"]
            group = "model_name"
          }
        }
        name = "estimated-cost-trend"
      },
      {
        type = 3
        content = {
          version       = "KqlItem/1.0"
          query         = <<-KQL
            AzureDiagnostics
            | where ResourceProvider == "MICROSOFT.COGNITIVESERVICES"
            | where Category == "AzureOpenAIRequestUsage"
            | extend props = parse_json(properties_s)
            | extend model_name = tostring(props.modelName)
            | summarize RequestCount = count() by bin(TimeGenerated, 1d), model_name
            | order by TimeGenerated desc
          KQL
          size          = 0
          timeContext   = { durationMs = 2592000000 }
          queryType     = 0
          resourceType  = "microsoft.operationalinsights/workspaces"
          visualization = "barchart"
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
