locals {
  log_analytics_query_pack = jsondecode(file("${local.asset_root}/dashboards/log-analytics/oci-wazuh-dashboard-queries.json"))
  dashboard_saved_searches = [
    for index, query in local.log_analytics_query_pack.queries : {
      id               = "ocid1.managementsavedsearch.oc1..${substr(sha256("${var.project_name}-${query.id}"), 0, 32)}"
      displayName      = query.title
      providerId       = "log-analytics"
      providerVersion  = "3.0.0"
      providerName     = "Logging Analytics"
      compartmentId    = local.effective_compartment_ocid
      isOobSavedSearch = false
      description      = "OCI Wazuh query: ${query.id}"
      nls              = {}
      type             = "WIDGET_SHOW_IN_DASHBOARD"
      uiConfig = {
        timeSelection = {
          timePeriod = "l24hour"
        }
        showTitle         = true
        visualizationType = query.visualization
        queryString       = query.query
        scopeFilters      = { filters = [], isGlobal = true }
        internalKey       = "${var.project_name}-${query.id}"
        vizType           = "lxSavedSearchWidgetType"
        enableWidgetInApp = true
      }
      dataConfig      = []
      screenImage     = " "
      metadataVersion = "2.0"
      widgetTemplate  = "visualizations/chartWidgetTemplate.html"
      widgetVM        = "jet-modules/dashboards/widgets/lxSavedSearchWidget"
      freeformTags    = local.common_freeform_tags
      definedTags     = {}
      parametersConfig = [
        {
          name        = "time"
          displayName = "$(bundle.globalSavedSearch.TIME)"
          required    = true
          hidden      = true
        },
        {
          name = "flex"
        }
      ]
      featuresConfig  = { crossService = { shared = false } }
      drilldownConfig = []
    }
  ]
  dashboard_tiles = [
    for index, query in local.log_analytics_query_pack.queries : {
      displayName     = query.title
      savedSearchId   = local.dashboard_saved_searches[index].id
      row             = floor(index / 2) * 3
      column          = (index % 2) * 6
      height          = 3
      width           = 6
      nls             = {}
      uiConfig        = local.dashboard_saved_searches[index].uiConfig
      dataConfig      = local.dashboard_saved_searches[index].dataConfig
      state           = "DEFAULT"
      drilldownConfig = []
      parametersMap = {
        time = "$(dashboard.params.time)"
      }
    }
  ]
  management_dashboard_import = jsonencode({
    dashboards = [{
      dashboardId       = "ocid1.managementdashboard.oc1..${substr(sha256("${var.project_name}-oci-wazuh-correlation"), 0, 32)}"
      providerId        = "log-analytics"
      providerName      = "Logging Analytics"
      providerVersion   = "3.0.0"
      tiles             = local.dashboard_tiles
      displayName       = "${var.project_name}-correlation"
      description       = "OCI Audit, VCN Flow, host, Sysmon, and Wazuh correlation queries."
      compartmentId     = local.effective_compartment_ocid
      isOobDashboard    = false
      isShowInHome      = false
      metadataVersion   = "2.0"
      isShowDescription = true
      screenImage       = ""
      nls               = {}
      uiConfig = {
        isFilteringEnabled = false
        isTimeRangeEnabled = true
        isRefreshEnabled   = true
      }
      dataConfig = []
      parametersConfig = [{
        name        = "time"
        displayName = "$(bundle.globalSavedSearch.TIME)"
        src         = "$(context.time)"
      }]
      featuresConfig  = { crossService = { shared = false } }
      drilldownConfig = []
      type            = "normal"
      isFavorite      = false
      savedSearches   = local.dashboard_saved_searches
      freeformTags    = local.common_freeform_tags
      definedTags     = {}
    }]
  })
}

resource "oci_management_dashboard_management_dashboards_import" "wazuh" {
  count                                  = local.effective_log_analytics ? 1 : 0
  import_details                         = local.management_dashboard_import
  override_same_name                     = "true"
  override_dashboard_compartment_ocid    = local.effective_compartment_ocid
  override_saved_search_compartment_ocid = local.effective_compartment_ocid

  depends_on = [oci_log_analytics_log_analytics_log_group.wazuh]
}
