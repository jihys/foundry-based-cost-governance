# -----------------------------------------------------------------------------
# Locals
# -----------------------------------------------------------------------------

locals {
  workbook_name = format(
    "%s-%s-%s-%s-%s",
    substr(md5("workbook-unified-cost-dashboard"), 0, 8),
    substr(md5("workbook-unified-cost-dashboard"), 8, 4),
    substr(md5("workbook-unified-cost-dashboard"), 12, 4),
    substr(md5("workbook-unified-cost-dashboard"), 16, 4),
    substr(md5("workbook-unified-cost-dashboard"), 20, 12)
  )

  workspace_union = join(",\n  ", [
    for team, ws_id in var.team_workspaces :
    "workspace('${ws_id}').AzureDiagnostics"
  ])

  workspace_metrics_union = join(",\n  ", [
    for team, ws_id in var.team_workspaces :
    "workspace('${ws_id}').AzureMetrics"
  ])

  workspace_ids = values(var.team_workspaces)
}

# -----------------------------------------------------------------------------
# Resource Group
# -----------------------------------------------------------------------------

resource "azurerm_resource_group" "unified" {
  name     = "rg-unified-cost-dashboard"
  location = var.location
}

# -----------------------------------------------------------------------------
# Unified Cost Dashboard Workbook
# -----------------------------------------------------------------------------

resource "azurerm_application_insights_workbook" "unified_dashboard" {
  name                = local.workbook_name
  location            = var.location
  resource_group_name = azurerm_resource_group.unified.name
  display_name        = "Unified Cost Dashboard - All Teams"
  source_id           = lower(values(var.team_workspaces)[0])

  data_json = jsonencode({
    version = "Notebook/1.0"
    items = [
      # ---------------------------------------------------------------------
      # Header
      # ---------------------------------------------------------------------
      {
        type = 1
        content = {
          json = "# Unified Cost Dashboard — All Teams\n팀별 AI 모델 토큰 사용량 및 비용 모니터링\n\nTeams: ${join(", ", keys(var.team_workspaces))}"
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
      # Panel 1: 팀별 일별 토큰 사용량 (bar chart)
      # ---------------------------------------------------------------------
      {
        type = 3
        content = {
          version                  = "KqlItem/1.0"
          query                    = <<-KQL
            let all_logs = union
              ${local.workspace_union};
            let all_metrics = union
              ${local.workspace_metrics_union};
            let team_tokens = all_metrics
            | where ResourceProvider == "MICROSOFT.COGNITIVESERVICES"
            | where MetricName in ("InputTokens", "OutputTokens")
            | extend team_name = extract("resourcegroups/rg-(.*)-ai-foundry", 1, _ResourceId)
            | summarize
                InputTokens = sumif(Total, MetricName == "InputTokens"),
                OutputTokens = sumif(Total, MetricName == "OutputTokens")
              by bin(TimeGenerated, 1d), team_name;
            let team_reqs = all_logs
            | where ResourceProvider == "MICROSOFT.COGNITIVESERVICES"
            | where Category == "RequestResponse"
            | extend team_name = extract("resourcegroups/rg-(.*)-ai-foundry", 1, _ResourceId)
            | summarize RequestCount = count() by bin(TimeGenerated, 1d), team_name;
            team_reqs
            | join kind=leftouter team_tokens on TimeGenerated, team_name
            | project TimeGenerated, team_name, RequestCount, InputTokens = coalesce(InputTokens, 0.0), OutputTokens = coalesce(OutputTokens, 0.0)
            | order by TimeGenerated desc
          KQL
          size                     = 0
          timeContextFromParameter = "TimeRange"
          queryType                = 0
          resourceType             = "microsoft.operationalinsights/workspaces"
          crossComponentResources  = local.workspace_ids
          visualization            = "barchart"
          chartSettings = {
            xAxis = "TimeGenerated"
            yAxis = ["InputTokens", "OutputTokens"]
            group = "team_name"
          }
        }
        name = "token-usage-daily"
      },
      # ---------------------------------------------------------------------
      # Panel 2: 팀별 모델 사용량 (table)
      # ---------------------------------------------------------------------
      {
        type = 3
        content = {
          version                  = "KqlItem/1.0"
          query                    = <<-KQL
            let all_metrics = union
              ${local.workspace_metrics_union};
            let all_logs = union
              ${local.workspace_union};
            let model_reqs = all_logs
            | where ResourceProvider == "MICROSOFT.COGNITIVESERVICES"
            | where Category == "RequestResponse"
            | extend team_name = extract("resourcegroups/rg-(.*)-ai-foundry", 1, _ResourceId)
            | extend model_name = tostring(parse_json(properties_s).modelName)
            | extend resp_bytes = todouble(parse_json(properties_s).responseLength)
            | summarize Requests = count(), TotalRespBytes = sum(resp_bytes), AvgDurationMs = round(avg(DurationMs), 1) by team_name, model_name;
            let team_total_resp = model_reqs | summarize TeamTotalResp = sum(TotalRespBytes) by team_name;
            let team_tokens = all_metrics
            | where ResourceProvider == "MICROSOFT.COGNITIVESERVICES"
            | where MetricName in ("InputTokens", "OutputTokens")
            | extend team_name = extract("resourcegroups/rg-(.*)-ai-foundry", 1, _ResourceId)
            | summarize
                TeamInputTokens = sumif(Total, MetricName == "InputTokens"),
                TeamOutputTokens = sumif(Total, MetricName == "OutputTokens")
              by team_name;
            model_reqs
            | join kind=inner team_total_resp on team_name
            | join kind=leftouter team_tokens on team_name
            | extend Weight = iff(TeamTotalResp > 0, TotalRespBytes / TeamTotalResp, 0.0)
            | extend InputTokens = round(coalesce(TeamInputTokens, 0.0) * Weight)
            | extend OutputTokens = round(coalesce(TeamOutputTokens, 0.0) * Weight)
            | extend TotalTokens = InputTokens + OutputTokens
            | project team_name, model_name, Requests, InputTokens, OutputTokens, TotalTokens, AvgDurationMs
            | order by team_name asc, TotalTokens desc
          KQL
          size                     = 0
          timeContextFromParameter = "TimeRange"
          queryType                = 0
          resourceType             = "microsoft.operationalinsights/workspaces"
          crossComponentResources  = local.workspace_ids
          visualization            = "table"
        }
        name = "model-usage-by-team"
      },
      # ---------------------------------------------------------------------
      # Panel 3: 팀별 예상 비용 추이 (line chart)
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
            let all_metrics = union
              ${local.workspace_metrics_union};
            let all_logs = union
              ${local.workspace_union};
            let team_tokens = all_metrics
            | where ResourceProvider == "MICROSOFT.COGNITIVESERVICES"
            | where MetricName in ("InputTokens", "OutputTokens")
            | extend team_name = extract("resourcegroups/rg-(.*)-ai-foundry", 1, _ResourceId)
            | summarize
                TeamInputTokens = sumif(Total, MetricName == "InputTokens"),
                TeamOutputTokens = sumif(Total, MetricName == "OutputTokens")
              by bin(TimeGenerated, 1d), team_name;
            let model_dist = all_logs
            | where ResourceProvider == "MICROSOFT.COGNITIVESERVICES"
            | where Category == "RequestResponse"
            | extend team_name = extract("resourcegroups/rg-(.*)-ai-foundry", 1, _ResourceId)
            | extend model_name = tostring(parse_json(properties_s).modelName)
            | extend resp_bytes = todouble(parse_json(properties_s).responseLength)
            | summarize TotalRespBytes = sum(resp_bytes) by bin(TimeGenerated, 1d), team_name, model_name;
            let day_team_total = model_dist | summarize DayTeamTotal = sum(TotalRespBytes) by TimeGenerated, team_name;
            model_dist
            | join kind=inner day_team_total on TimeGenerated, team_name
            | join kind=leftouter team_tokens on TimeGenerated, team_name
            | extend Weight = iff(DayTeamTotal > 0, TotalRespBytes / DayTeamTotal, 0.0)
            | extend ModelInput = coalesce(TeamInputTokens, 0.0) * Weight
            | extend ModelOutput = coalesce(TeamOutputTokens, 0.0) * Weight
            | lookup kind=leftouter model_pricing on model_name
            | extend EstCostUSD = round(ModelInput / 1000.0 * coalesce(input_per_1k, 0.001) + ModelOutput / 1000.0 * coalesce(output_per_1k, 0.002), 4)
            | summarize DailyCostUSD = round(sum(EstCostUSD), 4) by bin(TimeGenerated, 1d), team_name
            | order by TimeGenerated desc
          KQL
          size                     = 0
          timeContextFromParameter = "TimeRange"
          queryType                = 0
          resourceType             = "microsoft.operationalinsights/workspaces"
          crossComponentResources  = local.workspace_ids
          visualization            = "linechart"
          chartSettings = {
            xAxis = "TimeGenerated"
            yAxis = ["DailyCostUSD"]
            group = "team_name"
          }
        }
        name = "cost-trend-by-team"
      },
      # ---------------------------------------------------------------------
      # Panel 4: 팀별 일별 요청 수 (bar chart)
      # ---------------------------------------------------------------------
      {
        type = 3
        content = {
          version                  = "KqlItem/1.0"
          query                    = <<-KQL
            let all_logs = union
              ${local.workspace_union};
            all_logs
            | where ResourceProvider == "MICROSOFT.COGNITIVESERVICES"
            | where Category == "RequestResponse"
            | extend team_name = extract("resourcegroups/rg-(.*)-ai-foundry", 1, _ResourceId)
            | extend model_name = tostring(parse_json(properties_s).modelName)
            | summarize RequestCount = count() by bin(TimeGenerated, 1d), team_name, model_name
            | order by TimeGenerated desc
          KQL
          size                     = 0
          timeContextFromParameter = "TimeRange"
          queryType                = 0
          resourceType             = "microsoft.operationalinsights/workspaces"
          crossComponentResources  = local.workspace_ids
          visualization            = "barchart"
          chartSettings = {
            xAxis             = "TimeGenerated"
            yAxis             = ["RequestCount"]
            group             = "team_name"
            seriesLabelFormat = "{team_name} ({model_name})"
          }
        }
        name = "request-count-by-team"
      },
      # ---------------------------------------------------------------------
      # Panel 5 header: 팀 비교
      # ---------------------------------------------------------------------
      {
        type = 1
        content = {
          json = "## 팀 비교"
        }
        name = "team-comparison-header"
      },
      # ---------------------------------------------------------------------
      # Panel 5: 팀 비교 (table)
      # ---------------------------------------------------------------------
      {
        type = 3
        content = {
          version                  = "KqlItem/1.0"
          query                    = <<-KQL
            let all_metrics = union
              ${local.workspace_metrics_union};
            let all_logs = union
              ${local.workspace_union};
            let team_reqs = all_logs
            | where ResourceProvider == "MICROSOFT.COGNITIVESERVICES"
            | where Category == "RequestResponse"
            | extend team_name = extract("resourcegroups/rg-(.*)-ai-foundry", 1, _ResourceId)
            | summarize TotalRequests = count() by team_name;
            let team_tokens = all_metrics
            | where ResourceProvider == "MICROSOFT.COGNITIVESERVICES"
            | where MetricName in ("InputTokens", "OutputTokens")
            | extend team_name = extract("resourcegroups/rg-(.*)-ai-foundry", 1, _ResourceId)
            | summarize
                InputTokens = round(sumif(Total, MetricName == "InputTokens")),
                OutputTokens = round(sumif(Total, MetricName == "OutputTokens")),
                TotalTokens = round(sumif(Total, MetricName == "InputTokens") + sumif(Total, MetricName == "OutputTokens"))
              by team_name;
            team_reqs
            | join kind=leftouter team_tokens on team_name
            | extend InputTokens = coalesce(InputTokens, 0.0)
            | extend OutputTokens = coalesce(OutputTokens, 0.0)
            | extend TotalTokens = coalesce(TotalTokens, 0.0)
            | project team_name, TotalRequests, InputTokens, OutputTokens, TotalTokens
            | order by TotalRequests desc
          KQL
          size                     = 0
          timeContextFromParameter = "TimeRange"
          queryType                = 0
          resourceType             = "microsoft.operationalinsights/workspaces"
          crossComponentResources  = local.workspace_ids
          visualization            = "table"
          gridSettings = {
            sortBy = [{ itemKey = "TotalTokens", sortOrder = 2 }]
          }
        }
        name = "team-comparison"
      }
    ]
    fallbackResourceIds = []
  })
}
