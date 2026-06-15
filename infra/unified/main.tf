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
      # -----------------------------------------------------------------------
      # Header
      # -----------------------------------------------------------------------
      {
        type = 1
        content = {
          json = "# Unified Cost Dashboard — All Teams\nCross-team request activity and performance monitoring for Azure AI Services.\n\nTeams: ${join(", ", keys(var.team_workspaces))}"
        }
        name = "header"
      },
      # -----------------------------------------------------------------------
      # Panel 1: Token Usage Daily (bar chart)
      # -----------------------------------------------------------------------
      {
        type = 3
        content = {
          version                 = "KqlItem/1.0"
          query                   = <<-KQL
            let all_data = union
              ${local.workspace_union};
            all_data
            | where ResourceProvider == "MICROSOFT.COGNITIVESERVICES"
            | where Category == "RequestResponse"
            | extend team_name = extract("workspaces/law-(.*)", 1, _ResourceId)
            | extend model_name = tostring(parse_json(properties_s).modelName)
            | summarize
                RequestCount = count(),
                AvgDurationMs = round(avg(DurationMs), 1),
                TotalResponseBytes = sum(toint(parse_json(properties_s).responseLength))
              by bin(TimeGenerated, 1d), model_name, team_name
            | order by TimeGenerated desc
          KQL
          size                    = 0
          timeContext             = { durationMs = 2592000000 }
          queryType               = 0
          resourceType            = "microsoft.operationalinsights/workspaces"
          crossComponentResources = local.workspace_ids
          visualization           = "barchart"
          chartSettings = {
            xAxis             = "TimeGenerated"
            yAxis             = ["RequestCount"]
            group             = "model_name"
            seriesLabelFormat = "{model_name} ({team_name})"
          }
        }
        name = "request-activity-daily"
      },
      # -----------------------------------------------------------------------
      # Panel 2: Token Summary by Model (table)
      # -----------------------------------------------------------------------
      {
        type = 3
        content = {
          version                 = "KqlItem/1.0"
          query                   = <<-KQL
            let all_data = union
              ${local.workspace_union};
            all_data
            | where ResourceProvider == "MICROSOFT.COGNITIVESERVICES"
            | where Category == "RequestResponse"
            | extend team_name = extract("workspaces/law-(.*)", 1, _ResourceId)
            | extend model_name = tostring(parse_json(properties_s).modelName)
            | extend req_len = toint(parse_json(properties_s).requestLength)
            | extend resp_len = toint(parse_json(properties_s).responseLength)
            | summarize
                TotalRequests = count(),
                AvgDurationMs = round(avg(DurationMs), 1),
                TotalRequestBytes = sum(req_len),
                TotalResponseBytes = sum(resp_len)
              by model_name, team_name
            | order by TotalRequests desc
          KQL
          size                    = 0
          timeContext             = { durationMs = 2592000000 }
          queryType               = 0
          resourceType            = "microsoft.operationalinsights/workspaces"
          crossComponentResources = local.workspace_ids
          visualization           = "table"
        }
        name = "model-summary"
      },
      # -----------------------------------------------------------------------
      # Panel 3: Estimated Cost Trend (line chart)
      # -----------------------------------------------------------------------
      {
        type = 3
        content = {
          version                 = "KqlItem/1.0"
          query                   = <<-KQL
            let all_data = union
              ${local.workspace_union};
            all_data
            | where ResourceProvider == "MICROSOFT.COGNITIVESERVICES"
            | where Category == "RequestResponse"
            | extend team_name = extract("workspaces/law-(.*)", 1, _ResourceId)
            | extend model_name = tostring(parse_json(properties_s).modelName)
            | summarize
                AvgDurationMs = round(avg(DurationMs), 1),
                P95DurationMs = round(percentile(DurationMs, 95), 1),
                RequestCount = count()
              by bin(TimeGenerated, 1d), model_name, team_name
            | order by TimeGenerated desc
          KQL
          size                    = 0
          timeContext             = { durationMs = 2592000000 }
          queryType               = 0
          resourceType            = "microsoft.operationalinsights/workspaces"
          crossComponentResources = local.workspace_ids
          visualization           = "linechart"
          chartSettings = {
            xAxis             = "TimeGenerated"
            yAxis             = ["AvgDurationMs"]
            group             = "model_name"
            seriesLabelFormat = "{model_name} ({team_name})"
          }
        }
        name = "response-time-trend"
      },
      # -----------------------------------------------------------------------
      # Panel 4: Request Count Daily (bar chart)
      # -----------------------------------------------------------------------
      {
        type = 3
        content = {
          version                 = "KqlItem/1.0"
          query                   = <<-KQL
            let all_data = union
              ${local.workspace_union};
            all_data
            | where ResourceProvider == "MICROSOFT.COGNITIVESERVICES"
            | where Category == "RequestResponse"
            | extend team_name = extract("workspaces/law-(.*)", 1, _ResourceId)
            | extend model_name = tostring(parse_json(properties_s).modelName)
            | summarize RequestCount = count() by bin(TimeGenerated, 1d), model_name, team_name
            | order by TimeGenerated desc
          KQL
          size                    = 0
          timeContext             = { durationMs = 2592000000 }
          queryType               = 0
          resourceType            = "microsoft.operationalinsights/workspaces"
          crossComponentResources = local.workspace_ids
          visualization           = "barchart"
          chartSettings = {
            xAxis             = "TimeGenerated"
            yAxis             = ["RequestCount"]
            group             = "model_name"
            seriesLabelFormat = "{model_name} ({team_name})"
          }
        }
        name = "request-count-daily"
      },
      # -----------------------------------------------------------------------
      # Panel 5: Team Comparison (table)
      # -----------------------------------------------------------------------
      {
        type = 1
        content = {
          json = "## Team Comparison"
        }
        name = "team-comparison-header"
      },
      {
        type = 3
        content = {
          version                 = "KqlItem/1.0"
          query                   = <<-KQL
            let all_data = union
              ${local.workspace_union};
            all_data
            | where ResourceProvider == "MICROSOFT.COGNITIVESERVICES"
            | where Category == "RequestResponse"
            | extend team_name = extract("workspaces/law-(.*)", 1, _ResourceId)
            | extend model_name = tostring(parse_json(properties_s).modelName)
            | summarize
                TotalRequests = count(),
                AvgDurationMs = round(avg(DurationMs), 1),
                TotalResponseBytes = sum(toint(parse_json(properties_s).responseLength))
              by team_name
            | order by TotalRequests desc
          KQL
          size                    = 0
          timeContext             = { durationMs = 2592000000 }
          queryType               = 0
          resourceType            = "microsoft.operationalinsights/workspaces"
          crossComponentResources = local.workspace_ids
          visualization           = "table"
          gridSettings = {
            sortBy = [{ itemKey = "TotalRequests", sortOrder = 2 }]
          }
        }
        name = "team-comparison"
      }
    ]
    fallbackResourceIds = []
  })
}
