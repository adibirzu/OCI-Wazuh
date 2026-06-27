data "oci_log_analytics_namespaces" "this" {
  count          = local.effective_log_analytics ? 1 : 0
  compartment_id = local.effective_tenancy_ocid
}

locals {
  discovered_log_analytics_namespaces = local.effective_log_analytics ? try(
    data.oci_log_analytics_namespaces.this[0].namespace_collection[0].items,
    []
  ) : []
  log_analytics_namespace = var.log_analytics_namespace != "" ? var.log_analytics_namespace : try(
    local.discovered_log_analytics_namespaces[0].namespace,
    ""
  )
}

resource "terraform_data" "log_analytics_contract" {
  count = local.effective_log_analytics ? 1 : 0
  input = local.log_analytics_namespace

  lifecycle {
    precondition {
      condition     = local.log_analytics_namespace != ""
      error_message = "Log Analytics is enabled but no namespace is onboarded; set log_analytics_namespace after onboarding."
    }
  }
}

resource "oci_logging_log_group" "wazuh" {
  count          = local.effective_log_analytics ? 1 : 0
  compartment_id = local.effective_compartment_ocid
  display_name   = "${var.project_name}-wazuh-logs"
  description    = "Project-owned custom Wazuh alert logs."
  freeform_tags  = merge(local.common_freeform_tags, { role = "wazuh-alert-log-group" })
  defined_tags   = var.defined_tags
}

resource "oci_logging_log" "wazuh_alerts" {
  count              = local.effective_log_analytics ? 1 : 0
  display_name       = "${var.project_name}-wazuh-alerts"
  log_group_id       = oci_logging_log_group.wazuh[0].id
  log_type           = "CUSTOM"
  is_enabled         = true
  retention_duration = var.oci_log_retention_days
  freeform_tags      = merge(local.common_freeform_tags, { role = "wazuh-alert-log" })
  defined_tags       = var.defined_tags
}

resource "oci_logging_log" "windows_events" {
  count              = local.effective_log_analytics && local.effective_windows_mode != "skip" ? 1 : 0
  display_name       = "${var.project_name}-windows-events"
  log_group_id       = oci_logging_log_group.wazuh[0].id
  log_type           = "CUSTOM"
  is_enabled         = true
  retention_duration = var.oci_log_retention_days
  freeform_tags      = merge(local.common_freeform_tags, { role = "windows-event-log" })
  defined_tags       = var.defined_tags
}

resource "oci_logging_unified_agent_configuration" "wazuh_alerts" {
  count          = local.effective_log_analytics ? 1 : 0
  compartment_id = local.effective_compartment_ocid
  display_name   = "${var.project_name}-wazuh-alerts"
  description    = "Tail Wazuh alerts JSON into OCI Logging."
  is_enabled     = true
  freeform_tags  = merge(local.common_freeform_tags, { role = "wazuh-alert-agent-config" })
  defined_tags   = var.defined_tags

  group_association {
    group_list = [oci_identity_dynamic_group.wazuh_consumer.id]
  }

  service_configuration {
    configuration_type = "LOGGING"

    destination {
      log_object_id = oci_logging_log.wazuh_alerts[0].id
    }

    sources {
      source_type = "LOG_TAIL"
      name        = "wazuh-alerts-json"
      paths       = ["/var/ossec/logs/alerts/alerts.json"]

      parser {
        parser_type               = "NONE"
        is_estimate_current_event = true
      }
    }
  }
}

resource "oci_logging_unified_agent_configuration" "windows_events" {
  count          = local.effective_log_analytics && local.effective_windows_mode != "skip" ? 1 : 0
  compartment_id = local.effective_compartment_ocid
  display_name   = "${var.project_name}-windows-events"
  description    = "Collect Security, System, Application, and Sysmon channels from selected Windows targets."
  is_enabled     = true
  freeform_tags  = merge(local.common_freeform_tags, { role = "windows-event-agent-config" })
  defined_tags   = var.defined_tags

  group_association {
    group_list = [module.windows.target_dynamic_group_id]
  }

  service_configuration {
    configuration_type = "LOGGING"

    destination {
      log_object_id = oci_logging_log.windows_events[0].id
    }

    sources {
      source_type = "WINDOWS_EVENT_LOG"
      name        = "windows-security-system-application-sysmon"
      channels = [
        "Application",
        "System",
        "Security",
        "Microsoft-Windows-Sysmon/Operational",
      ]
    }
  }
}

resource "oci_identity_policy" "wazuh_log_publish" {
  count          = local.effective_log_analytics ? 1 : 0
  compartment_id = local.effective_tenancy_ocid
  name           = "${var.project_name}-wazuh-log-publish"
  description    = "Allow only the Wazuh instance to publish its custom alert log."
  statements = [
    "Allow dynamic-group ${oci_identity_dynamic_group.wazuh_consumer.name} to use log-content in compartment id ${local.effective_compartment_ocid}",
    "Allow dynamic-group ${oci_identity_dynamic_group.wazuh_consumer.name} to read log-groups in compartment id ${local.effective_compartment_ocid}",
  ]
  freeform_tags = local.common_freeform_tags
  defined_tags  = var.defined_tags
}

resource "oci_identity_policy" "windows_log_publish" {
  count          = local.effective_log_analytics && local.effective_windows_mode != "skip" ? 1 : 0
  compartment_id = local.effective_tenancy_ocid
  name           = "${var.project_name}-windows-log-publish"
  description    = "Allow only selected Windows targets to publish project Windows event logs."
  statements = [
    "Allow dynamic-group ${module.windows.target_dynamic_group_name} to use log-content in compartment id ${local.effective_compartment_ocid}",
    "Allow dynamic-group ${module.windows.target_dynamic_group_name} to read log-groups in compartment id ${local.effective_compartment_ocid}",
  ]
  freeform_tags = local.common_freeform_tags
  defined_tags  = var.defined_tags
}

resource "oci_log_analytics_log_analytics_log_group" "wazuh" {
  count          = local.effective_log_analytics ? 1 : 0
  compartment_id = local.effective_compartment_ocid
  namespace      = local.log_analytics_namespace
  display_name   = "${var.project_name}-log-analytics"
  description    = "OCI, host, and Wazuh correlation logs."
  freeform_tags  = merge(local.common_freeform_tags, { role = "log-analytics" })
  defined_tags   = var.defined_tags

  depends_on = [terraform_data.log_analytics_contract]
}

locals {
  linux_log_analytics_entities = {
    wazuh = {
      id          = module.wazuh_server.instance_id
      hostname    = "${var.project_name}-wazuh-aio"
      entity_type = "Host (Linux)"
    }
    ol9 = {
      id          = module.compute.instance_ids[1]
      hostname    = "${var.project_name}-ol9-agent"
      entity_type = "Host (Linux)"
    }
    ubuntu = {
      id          = module.compute.instance_ids[2]
      hostname    = "${var.project_name}-ubuntu-agent"
      entity_type = "Host (Linux)"
    }
  }
}

resource "oci_log_analytics_log_analytics_entity" "linux" {
  for_each = local.effective_log_analytics ? local.linux_log_analytics_entities : {}

  compartment_id    = local.effective_compartment_ocid
  namespace         = local.log_analytics_namespace
  entity_type_name  = each.value.entity_type
  name              = each.value.hostname
  hostname          = each.value.hostname
  cloud_resource_id = each.value.id
  timezone_region   = "UTC"
  freeform_tags     = merge(local.common_freeform_tags, { role = "log-analytics-entity" })
  defined_tags      = var.defined_tags
}

resource "oci_log_analytics_log_analytics_entity" "windows" {
  for_each = local.effective_log_analytics && local.effective_windows_mode != "skip" ? toset(module.windows.target_names) : toset([])

  compartment_id    = local.effective_compartment_ocid
  namespace         = local.log_analytics_namespace
  entity_type_name  = "Host (Windows)"
  name              = each.value
  hostname          = each.value
  cloud_resource_id = nonsensitive(module.windows.target_instance_map[each.value])
  timezone_region   = "UTC"
  freeform_tags     = merge(local.common_freeform_tags, { role = "log-analytics-entity" })
  defined_tags      = var.defined_tags
}

resource "oci_identity_policy" "sch_log_analytics_target" {
  count          = local.effective_log_analytics ? 1 : 0
  compartment_id = local.effective_tenancy_ocid
  name           = "${var.project_name}-sch-log-analytics-target"
  description    = "Allow only the project Service Connector to upload to the project Log Analytics group."
  statements = [
    "Allow any-user to read log-content in compartment id ${local.effective_compartment_ocid} where request.principal.type='serviceconnector'",
    "Allow any-user to use loganalytics-log-group in compartment id ${local.effective_compartment_ocid} where all {request.principal.type='serviceconnector', target.loganalytics-log-group.id='${oci_log_analytics_log_analytics_log_group.wazuh[0].id}', request.principal.compartment.id='${local.effective_compartment_ocid}'}",
  ]
  freeform_tags = local.common_freeform_tags
  defined_tags  = var.defined_tags
}

resource "oci_sch_service_connector" "wazuh_to_log_analytics" {
  count          = local.effective_log_analytics ? 1 : 0
  compartment_id = local.effective_compartment_ocid
  display_name   = "${var.project_name}-wazuh-alerts-to-log-analytics"
  description    = "Forward project Wazuh custom logs to OCI Log Analytics."
  freeform_tags  = merge(local.common_freeform_tags, { role = "wazuh-log-analytics-connector" })
  defined_tags   = var.defined_tags

  source {
    kind = "logging"

    dynamic "log_sources" {
      for_each = merge(
        { wazuh = oci_logging_log.wazuh_alerts[0].id },
        local.effective_windows_mode != "skip" ? { windows = oci_logging_log.windows_events[0].id } : {},
      )
      content {
        compartment_id = local.effective_compartment_ocid
        log_group_id   = oci_logging_log_group.wazuh[0].id
        log_id         = log_sources.value
      }
    }
  }

  target {
    kind         = "loggingAnalytics"
    log_group_id = oci_log_analytics_log_analytics_log_group.wazuh[0].id
  }

  depends_on = [oci_identity_policy.sch_log_analytics_target]
}
