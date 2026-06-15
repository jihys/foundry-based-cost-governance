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
  source_id           = "azure monitor"

  data_json = jsonencode({
    version = "Notebook/1.0"
    items = [
      # -----------------------------------------------------------------------
      # Header
      # -----------------------------------------------------------------------
      {
        type = 1
        content = {
          json = "# Unified Cost Dashboard — All Teams\nCross-team token usage and cost monitoring for Azure AI Services.\n\nTeams: ${join(", ", keys(var.team_workspaces))}"
        }
        name = "header"
      },
      # -----------------------------------------------------------------------
      # Panel 1: Token Usage Daily (bar chart)
      # -----------------------------------------------------------------------
      {
        type = 3
        content = {
          version       = "KqlItem/1.0"
          query         = <<-KQL
            let all_data = union
              ${local.workspace_union};
            all_data
            | where ResourceProvider == "MICROSOFT.COGNITIVESERVICES"
            | where Category == "AzureOpenAIRequestUsage"
            | extend team_name = extract("workspaces/law-(.*)", 1, _ResourceId)
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
              by bin(TimeGenerated, 1d), model_name, team_name
            | order by TimeGenerated desc
          KQL
          size          = 0
          timeContext   = { durationMs = 2592000000 }
          queryType     = 0
          resourceType  = "microsoft.operationalinsights/workspaces"
          visualization = "barchart"
          chartSettings = {
            xAxis     = "TimeGenerated"
            yAxis     = ["TotalTokens"]
            group     = "model_name"
            seriesLabelFormat = "{model_name} ({team_name})"
          }
        }
        name = "token-usage-daily"
      },
      # -----------------------------------------------------------------------
      # Panel 2: Token Summary by Model (table)
      # -----------------------------------------------------------------------
      {
        type = 3
        content = {
          version       = "KqlItem/1.0"
          query         = <<-KQL
            let all_data = union
              ${local.workspace_union};
            all_data
            | where ResourceProvider == "MICROSOFT.COGNITIVESERVICES"
            | where Category == "AzureOpenAIRequestUsage"
            | extend team_name = extract("workspaces/law-(.*)", 1, _ResourceId)
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
              by model_name, team_name
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
      # -----------------------------------------------------------------------
      # Panel 3: Estimated Cost Trend (line chart)
      # -----------------------------------------------------------------------
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
            let all_data = union
              ${local.workspace_union};
            all_data
            | where ResourceProvider == "MICROSOFT.COGNITIVESERVICES"
            | where Category == "AzureOpenAIRequestUsage"
            | extend team_name = extract("workspaces/law-(.*)", 1, _ResourceId)
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
              by bin(TimeGenerated, 1d), model_name, team_name
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
            seriesLabelFormat = "{model_name} ({team_name})"
          }
        }
        name = "estimated-cost-trend"
      },
      # -----------------------------------------------------------------------
      # Panel 4: Request Count Daily (bar chart)
      # -----------------------------------------------------------------------
      {
        type = 3
        content = {
          version       = "KqlItem/1.0"
          query         = <<-KQL
            let all_data = union
              ${local.workspace_union};
            all_data
            | where ResourceProvider == "MICROSOFT.COGNITIVESERVICES"
            | where Category == "AzureOpenAIRequestUsage"
            | extend team_name = extract("workspaces/law-(.*)", 1, _ResourceId)
            | extend props = parse_json(properties_s)
            | extend model_name = tostring(props.modelName)
            | summarize RequestCount = count() by bin(TimeGenerated, 1d), model_name, team_name
            | order by TimeGenerated desc
          KQL
          size          = 0
          timeContext   = { durationMs = 2592000000 }
          queryType     = 0
          resourceType  = "microsoft.operationalinsights/workspaces"
          visualization = "barchart"
          chartSettings = {
            xAxis     = "TimeGenerated"
            yAxis     = ["RequestCount"]
            group     = "model_name"
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
          version       = "KqlItem/1.0"
          query         = <<-KQL
            let model_pricing = datatable(model_name: string, input_price_per_1k: real, output_price_per_1k: real) [
                "gpt-4o",                  0.0025,  0.01,
                "gpt-4.1-mini",            0.0004,  0.0016,
                "o3-mini",                 0.0011,  0.0044,
                "text-embedding-3-large",  0.00013, 0.0
            ];
            let all_data = union
              ${local.workspace_union};
            all_data
            | where ResourceProvider == "MICROSOFT.COGNITIVESERVICES"
            | where Category == "AzureOpenAIRequestUsage"
            | extend team_name = extract("workspaces/law-(.*)", 1, _ResourceId)
            | extend props = parse_json(properties_s)
            | extend model_name = tostring(props.modelName)
            | extend prompt_tokens = toint(props.promptTokens)
            | extend completion_tokens = toint(props.completionTokens)
            | extend total_tokens = prompt_tokens + completion_tokens
            | lookup kind=leftouter model_pricing on model_name
            | extend input_cost = prompt_tokens / 1000.0 * coalesce(input_price_per_1k, 0.001)
            | extend output_cost = completion_tokens / 1000.0 * coalesce(output_price_per_1k, 0.002)
            | extend total_cost = input_cost + output_cost
            | summarize
                TotalPromptTokens = sum(prompt_tokens),
                TotalCompletionTokens = sum(completion_tokens),
                TotalTokens = sum(total_tokens),
                TotalRequests = count(),
                EstimatedCostUSD = round(sum(total_cost), 4)
              by team_name
            | order by EstimatedCostUSD desc
          KQL
          size          = 0
          timeContext   = { durationMs = 2592000000 }
          queryType     = 0
          resourceType  = "microsoft.operationalinsights/workspaces"
          visualization = "table"
          gridSettings = {
            sortBy = [{ itemKey = "EstimatedCostUSD", sortOrder = 2 }]
          }
        }
        name = "team-comparison"
      }
    ]
    fallbackResourceIds = []
  })
}
