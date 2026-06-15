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
      # ---------------------------------------------------------------------
      # Header
      # ---------------------------------------------------------------------
      {
        type = 1
        content = {
          json = "# Cost Dashboard — ${var.team_name}\n팀별 AI 모델 토큰 사용량 및 비용 모니터링"
        }
        name = "header"
      },
      # ---------------------------------------------------------------------
      # Time Range Parameter
      # ---------------------------------------------------------------------
      {
        type = 9
        content = {
          version = "KqlParameterItem/1.0"
          parameters = [
            {
              id         = "time_range"
              version    = "KqlParameterItem/1.0"
              name       = "TimeRange"
              label      = "시간 범위"
              type       = 4
              isRequired = true
              value = {
                durationMs = 86400000
              }
              typeSettings = {
                selectableValues = [
                  { durationMs = 3600000, displayText = "Last 1 hour" },
                  { durationMs = 14400000, displayText = "Last 4 hours" },
                  { durationMs = 43200000, displayText = "Last 12 hours" },
                  { durationMs = 86400000, displayText = "Last 24 hours", isInitialTime = true },
                  { durationMs = 172800000, displayText = "Last 2 days" },
                  { durationMs = 604800000, displayText = "Last 7 days" },
                  { durationMs = 2592000000, displayText = "Last 30 days" }
                ]
                allowCustom = true
              }
            }
          ]
          style = "pills"
        }
        name = "time-range-parameter"
      },
      # ---------------------------------------------------------------------
      # Panel 1: 일별 토큰 사용량 (bar chart)
      # ---------------------------------------------------------------------
      {
        type = 3
        content = {
          version                  = "KqlItem/1.0"
          query                    = <<-KQL
            let tokens = AzureMetrics
            | where ResourceProvider == "MICROSOFT.COGNITIVESERVICES"
            | where MetricName in ("InputTokens", "OutputTokens")
            | summarize
                MetricsInput = sumif(Total, MetricName == "InputTokens"),
                MetricsOutput = sumif(Total, MetricName == "OutputTokens")
              by bin(TimeGenerated, 1d);
            let bytes = AzureDiagnostics
            | where ResourceProvider == "MICROSOFT.COGNITIVESERVICES"
            | where Category == "RequestResponse"
            | extend req_bytes = todouble(parse_json(properties_s).requestLength)
            | extend resp_bytes = todouble(parse_json(properties_s).responseLength)
            | summarize TotalReqBytes = sum(req_bytes), TotalRespBytes = sum(resp_bytes) by bin(TimeGenerated, 1d);
            bytes
            | join kind=leftouter tokens on TimeGenerated
            | extend InputTokens = iff(coalesce(MetricsInput, 0.0) > 0, round(MetricsInput), round(TotalReqBytes / 8.0))
            | extend OutputTokens = iff(coalesce(MetricsOutput, 0.0) > 0, round(MetricsOutput), round(TotalRespBytes / 18.0))
            | extend TotalTokens = InputTokens + OutputTokens
            | project TimeGenerated, InputTokens, OutputTokens, TotalTokens
            | order by TimeGenerated desc
          KQL
          size                     = 0
          timeContextFromParameter = "TimeRange"
          queryType                = 0
          resourceType             = "microsoft.operationalinsights/workspaces"
          crossComponentResources  = [azurerm_log_analytics_workspace.main.id]
          visualization            = "barchart"
          chartSettings = {
            xAxis = "TimeGenerated"
            yAxis = ["InputTokens", "OutputTokens"]
          }
        }
        name = "token-usage-daily"
      },
      # ---------------------------------------------------------------------
      # Panel 2: 모델별 사용량 요약 (table)
      # ---------------------------------------------------------------------
      {
        type = 3
        content = {
          version                  = "KqlItem/1.0"
          query                    = <<-KQL
            let model_reqs = AzureDiagnostics
            | where ResourceProvider == "MICROSOFT.COGNITIVESERVICES"
            | where Category == "RequestResponse"
            | extend model_name = tostring(parse_json(properties_s).modelName)
            | extend req_bytes = todouble(parse_json(properties_s).requestLength)
            | extend resp_bytes = todouble(parse_json(properties_s).responseLength)
            | summarize
                Requests = count(),
                AvgDurationMs = round(avg(DurationMs), 1),
                TotalReqBytes = sum(req_bytes),
                TotalRespBytes = sum(resp_bytes)
              by model_name;
            let total_req = toscalar(model_reqs | summarize sum(TotalReqBytes));
            let total_resp = toscalar(model_reqs | summarize sum(TotalRespBytes));
            let total_input = toscalar(AzureMetrics | where ResourceProvider == "MICROSOFT.COGNITIVESERVICES" | where MetricName == "InputTokens" | summarize sum(Total));
            let total_output = toscalar(AzureMetrics | where ResourceProvider == "MICROSOFT.COGNITIVESERVICES" | where MetricName == "OutputTokens" | summarize sum(Total));
            model_reqs
            | extend ReqWeight = iff(total_req > 0, TotalReqBytes / total_req, 0.0)
            | extend RespWeight = iff(total_resp > 0, TotalRespBytes / total_resp, 0.0)
            | extend InputTokens = iff(coalesce(total_input, 0.0) > 0, round(total_input * ReqWeight), round(TotalReqBytes / 8.0))
            | extend OutputTokens = iff(coalesce(total_output, 0.0) > 0, round(total_output * RespWeight), round(TotalRespBytes / 18.0))
            | extend TotalTokens = InputTokens + OutputTokens
            | project model_name, Requests, InputTokens, OutputTokens, TotalTokens, AvgDurationMs
            | order by TotalTokens desc
          KQL
          size                     = 0
          timeContextFromParameter = "TimeRange"
          queryType                = 0
          resourceType             = "microsoft.operationalinsights/workspaces"
          crossComponentResources  = [azurerm_log_analytics_workspace.main.id]
          visualization            = "table"
        }
        name = "model-usage-summary"
      },
      # ---------------------------------------------------------------------
      # Panel 3: 예상 비용 추이 (line chart)
      # ---------------------------------------------------------------------
      {
        type = 3
        content = {
          version                  = "KqlItem/1.0"
          query                    = <<-KQL
            let model_pricing = datatable(model_name: string, input_per_1k: real, output_per_1k: real) [
                "gpt-4o",             0.0025,  0.01,
                "gpt-4.1-mini",       0.0004,  0.0016,
                "gpt-5.4-mini",       0.0004,  0.0016,
                "o3-mini",            0.0011,  0.0044,
                "text-embedding-3-large", 0.00013, 0.0
            ];
            let hourly_tokens = AzureMetrics
            | where ResourceProvider == "MICROSOFT.COGNITIVESERVICES"
            | where MetricName in ("InputTokens", "OutputTokens")
            | summarize
                InputTokens = sumif(Total, MetricName == "InputTokens"),
                OutputTokens = sumif(Total, MetricName == "OutputTokens")
              by bin(TimeGenerated, 1d);
            let hourly_models = AzureDiagnostics
            | where ResourceProvider == "MICROSOFT.COGNITIVESERVICES"
            | where Category == "RequestResponse"
            | extend model_name = tostring(parse_json(properties_s).modelName)
            | extend req_bytes = todouble(parse_json(properties_s).requestLength)
            | extend resp_bytes = todouble(parse_json(properties_s).responseLength)
            | summarize TotalRespBytes = sum(resp_bytes), TotalReqBytes = sum(req_bytes), Requests = count() by bin(TimeGenerated, 1d), model_name;
            let daily_total_resp = hourly_models | summarize DayTotalResp = sum(TotalRespBytes), DayTotalReq = sum(TotalReqBytes) by TimeGenerated;
            hourly_models
            | join kind=inner daily_total_resp on TimeGenerated
            | join kind=leftouter hourly_tokens on TimeGenerated
            | extend Weight = iff(DayTotalResp > 0, TotalRespBytes / DayTotalResp, 0.0)
            | extend ReqWeight = iff(DayTotalReq > 0, TotalReqBytes / DayTotalReq, 0.0)
            | extend ModelInputTokens = iff(coalesce(InputTokens, 0.0) > 0, InputTokens * ReqWeight, TotalReqBytes / 8.0)
            | extend ModelOutputTokens = iff(coalesce(OutputTokens, 0.0) > 0, OutputTokens * Weight, TotalRespBytes / 18.0)
            | lookup kind=leftouter model_pricing on model_name
            | extend EstCostUSD = round(ModelInputTokens / 1000.0 * coalesce(input_per_1k, 0.001) + ModelOutputTokens / 1000.0 * coalesce(output_per_1k, 0.002), 4)
            | project TimeGenerated, model_name, EstCostUSD
            | order by TimeGenerated desc
          KQL
          size                     = 0
          timeContextFromParameter = "TimeRange"
          queryType                = 0
          resourceType             = "microsoft.operationalinsights/workspaces"
          crossComponentResources  = [azurerm_log_analytics_workspace.main.id]
          visualization            = "linechart"
          chartSettings = {
            xAxis = "TimeGenerated"
            yAxis = ["EstCostUSD"]
            group = "model_name"
          }
        }
        name = "estimated-cost-trend"
      },
      # ---------------------------------------------------------------------
      # Panel 4: 일별 요청 수 (bar chart)
      # ---------------------------------------------------------------------
      {
        type = 3
        content = {
          version                  = "KqlItem/1.0"
          query                    = <<-KQL
            AzureDiagnostics
            | where ResourceProvider == "MICROSOFT.COGNITIVESERVICES"
            | where Category == "RequestResponse"
            | extend model_name = tostring(parse_json(properties_s).modelName)
            | summarize RequestCount = count() by bin(TimeGenerated, 1d), model_name
            | order by TimeGenerated desc
          KQL
          size                     = 0
          timeContextFromParameter = "TimeRange"
          queryType                = 0
          resourceType             = "microsoft.operationalinsights/workspaces"
          crossComponentResources  = [azurerm_log_analytics_workspace.main.id]
          visualization            = "barchart"
          chartSettings = {
            xAxis = "TimeGenerated"
            yAxis = ["RequestCount"]
            group = "model_name"
          }
        }
        name = "request-count-daily"
      },
      # ---------------------------------------------------------------------
      # Panel 5: 응답 성능 (line chart)
      # ---------------------------------------------------------------------
      {
        type = 3
        content = {
          version                  = "KqlItem/1.0"
          query                    = <<-KQL
            AzureDiagnostics
            | where ResourceProvider == "MICROSOFT.COGNITIVESERVICES"
            | where Category == "RequestResponse"
            | extend model_name = tostring(parse_json(properties_s).modelName)
            | summarize
                AvgDurationMs = round(avg(DurationMs), 1),
                P95DurationMs = round(percentile(DurationMs, 95), 1)
              by bin(TimeGenerated, 1d), model_name
            | order by TimeGenerated desc
          KQL
          size                     = 0
          timeContextFromParameter = "TimeRange"
          queryType                = 0
          resourceType             = "microsoft.operationalinsights/workspaces"
          crossComponentResources  = [azurerm_log_analytics_workspace.main.id]
          visualization            = "linechart"
          chartSettings = {
            xAxis = "TimeGenerated"
            yAxis = ["AvgDurationMs"]
            group = "model_name"
          }
        }
        name = "response-performance"
      }
    ]
    fallbackResourceIds = []
  })
}
