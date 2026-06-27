data "oci_core_services" "all" {
  count = var.mode == "create" ? 1 : 0

  filter {
    name   = "name"
    values = ["All .* Services In Oracle Services Network"]
    regex  = true
  }
}

data "oci_core_subnet" "bastion" {
  count     = var.mode == "existing" ? 1 : 0
  subnet_id = var.existing_bastion_subnet_id
}

data "oci_core_subnet" "workload" {
  count     = var.mode == "existing" ? 1 : 0
  subnet_id = var.existing_workload_subnet_id
}

data "oci_core_vcn" "workload" {
  count  = var.mode == "existing" ? 1 : 0
  vcn_id = data.oci_core_subnet.workload[0].vcn_id
}

locals {
  bastion_subnet_id              = var.mode == "create" ? oci_core_subnet.bastion[0].id : data.oci_core_subnet.bastion[0].id
  workload_subnet_id             = var.mode == "create" ? oci_core_subnet.workload[0].id : data.oci_core_subnet.workload[0].id
  bastion_vcn_id                 = var.mode == "create" ? oci_core_vcn.this[0].id : data.oci_core_subnet.bastion[0].vcn_id
  workload_vcn_id                = var.mode == "create" ? oci_core_vcn.this[0].id : data.oci_core_subnet.workload[0].vcn_id
  workload_vcn_compartment_id    = var.mode == "create" ? var.compartment_id : data.oci_core_vcn.workload[0].compartment_id
  workload_subnet_compartment_id = var.mode == "create" ? var.compartment_id : data.oci_core_subnet.workload[0].compartment_id
  bastion_cidr                   = var.mode == "create" ? var.bastion_subnet_cidr : data.oci_core_subnet.bastion[0].cidr_block
  workload_cidr                  = var.mode == "create" ? var.workload_subnet_cidr : data.oci_core_subnet.workload[0].cidr_block
}

resource "terraform_data" "network_contract" {
  input = var.mode

  lifecycle {
    precondition {
      condition     = var.mode == "create" || try(!data.oci_core_subnet.bastion[0].prohibit_public_ip_on_vnic, false)
      error_message = "The existing bastion subnet must permit a public IP on the bastion VNIC."
    }
    precondition {
      condition     = var.mode == "create" || try(data.oci_core_subnet.workload[0].prohibit_public_ip_on_vnic, false)
      error_message = "The existing workload subnet must prohibit public IPs on VNICs."
    }
  }
}

resource "oci_core_vcn" "this" {
  count          = var.mode == "create" ? 1 : 0
  compartment_id = var.compartment_id
  cidr_blocks    = [var.vcn_cidr]
  display_name   = "${var.project_name}-vcn"
  dns_label      = "wazuhlab"
  freeform_tags  = merge(var.freeform_tags, { role = "network" })
  defined_tags   = var.defined_tags
}

resource "oci_core_internet_gateway" "this" {
  count          = var.mode == "create" ? 1 : 0
  compartment_id = var.compartment_id
  vcn_id         = oci_core_vcn.this[0].id
  display_name   = "${var.project_name}-internet-gateway"
  enabled        = true
  freeform_tags  = merge(var.freeform_tags, { role = "internet-gateway" })
  defined_tags   = var.defined_tags
}

resource "oci_core_nat_gateway" "this" {
  count          = var.mode == "create" ? 1 : 0
  compartment_id = var.compartment_id
  vcn_id         = oci_core_vcn.this[0].id
  display_name   = "${var.project_name}-nat-gateway"
  freeform_tags  = merge(var.freeform_tags, { role = "nat-gateway" })
  defined_tags   = var.defined_tags
}

resource "oci_core_service_gateway" "this" {
  count          = var.mode == "create" ? 1 : 0
  compartment_id = var.compartment_id
  vcn_id         = oci_core_vcn.this[0].id
  display_name   = "${var.project_name}-service-gateway"
  freeform_tags  = merge(var.freeform_tags, { role = "service-gateway" })
  defined_tags   = var.defined_tags

  services {
    service_id = data.oci_core_services.all[0].services[0].id
  }
}

resource "oci_core_route_table" "public" {
  count          = var.mode == "create" ? 1 : 0
  compartment_id = var.compartment_id
  vcn_id         = oci_core_vcn.this[0].id
  display_name   = "${var.project_name}-public-routes"
  freeform_tags  = merge(var.freeform_tags, { role = "public-routes" })
  defined_tags   = var.defined_tags

  route_rules {
    destination       = "0.0.0.0/0"
    destination_type  = "CIDR_BLOCK"
    network_entity_id = oci_core_internet_gateway.this[0].id
  }
}

resource "oci_core_route_table" "private" {
  count          = var.mode == "create" ? 1 : 0
  compartment_id = var.compartment_id
  vcn_id         = oci_core_vcn.this[0].id
  display_name   = "${var.project_name}-private-routes"
  freeform_tags  = merge(var.freeform_tags, { role = "private-routes" })
  defined_tags   = var.defined_tags

  route_rules {
    destination       = "0.0.0.0/0"
    destination_type  = "CIDR_BLOCK"
    network_entity_id = oci_core_nat_gateway.this[0].id
  }

  route_rules {
    destination       = data.oci_core_services.all[0].services[0].cidr_block
    destination_type  = "SERVICE_CIDR_BLOCK"
    network_entity_id = oci_core_service_gateway.this[0].id
  }
}

resource "oci_core_security_list" "public" {
  count          = var.mode == "create" ? 1 : 0
  compartment_id = var.compartment_id
  vcn_id         = oci_core_vcn.this[0].id
  display_name   = "${var.project_name}-public-default-deny"
  freeform_tags  = merge(var.freeform_tags, { role = "public-security-list" })
  defined_tags   = var.defined_tags

  egress_security_rules {
    protocol    = "all"
    destination = "0.0.0.0/0"
  }
}

resource "oci_core_security_list" "private" {
  count          = var.mode == "create" ? 1 : 0
  compartment_id = var.compartment_id
  vcn_id         = oci_core_vcn.this[0].id
  display_name   = "${var.project_name}-private-default-deny"
  freeform_tags  = merge(var.freeform_tags, { role = "private-security-list" })
  defined_tags   = var.defined_tags

  egress_security_rules {
    protocol    = "all"
    destination = "0.0.0.0/0"
  }
}

resource "oci_core_subnet" "bastion" {
  count                      = var.mode == "create" ? 1 : 0
  compartment_id             = var.compartment_id
  vcn_id                     = oci_core_vcn.this[0].id
  cidr_block                 = var.bastion_subnet_cidr
  display_name               = "${var.project_name}-bastion-subnet"
  dns_label                  = "bastion"
  prohibit_public_ip_on_vnic = false
  prohibit_internet_ingress  = false
  route_table_id             = oci_core_route_table.public[0].id
  security_list_ids          = [oci_core_security_list.public[0].id]
  freeform_tags              = merge(var.freeform_tags, { role = "bastion-subnet" })
  defined_tags               = var.defined_tags
}

resource "oci_core_subnet" "workload" {
  count                      = var.mode == "create" ? 1 : 0
  compartment_id             = var.compartment_id
  vcn_id                     = oci_core_vcn.this[0].id
  cidr_block                 = var.workload_subnet_cidr
  display_name               = "${var.project_name}-workload-subnet"
  dns_label                  = "workload"
  prohibit_public_ip_on_vnic = true
  prohibit_internet_ingress  = true
  route_table_id             = oci_core_route_table.private[0].id
  security_list_ids          = [oci_core_security_list.private[0].id]
  freeform_tags              = merge(var.freeform_tags, { role = "workload-subnet" })
  defined_tags               = var.defined_tags
}

resource "oci_core_network_security_group" "bastion" {
  compartment_id = var.compartment_id
  vcn_id         = local.bastion_vcn_id
  display_name   = "${var.project_name}-bastion-nsg"
  freeform_tags  = merge(var.freeform_tags, { role = "bastion-nsg" })
  defined_tags   = var.defined_tags
}

resource "oci_core_network_security_group" "wazuh" {
  compartment_id = var.compartment_id
  vcn_id         = local.workload_vcn_id
  display_name   = "${var.project_name}-wazuh-nsg"
  freeform_tags  = merge(var.freeform_tags, { role = "wazuh-nsg" })
  defined_tags   = var.defined_tags
}

resource "oci_core_network_security_group" "agents" {
  compartment_id = var.compartment_id
  vcn_id         = local.workload_vcn_id
  display_name   = "${var.project_name}-agents-nsg"
  freeform_tags  = merge(var.freeform_tags, { role = "agents-nsg" })
  defined_tags   = var.defined_tags
}

resource "oci_core_network_security_group_security_rule" "bastion_ssh" {
  network_security_group_id = oci_core_network_security_group.bastion.id
  direction                 = "INGRESS"
  protocol                  = "6"
  source                    = var.operator_cidr
  source_type               = "CIDR_BLOCK"

  tcp_options {
    destination_port_range {
      min = 22
      max = 22
    }
  }
}

resource "oci_core_network_security_group_security_rule" "wazuh_from_bastion" {
  for_each = toset(["22", "443", "55000"])

  network_security_group_id = oci_core_network_security_group.wazuh.id
  direction                 = "INGRESS"
  protocol                  = "6"
  source                    = local.bastion_cidr
  source_type               = "CIDR_BLOCK"

  tcp_options {
    destination_port_range {
      min = tonumber(each.value)
      max = tonumber(each.value)
    }
  }
}

resource "oci_core_network_security_group_security_rule" "wazuh_enrollment" {
  for_each = merge(
    {
      for port in [1514, 1515] :
      "workload-${port}" => { cidr = local.workload_cidr, port = port }
    },
    {
      for pair in setproduct(range(length(var.goad_agent_cidrs)), [1514, 1515]) :
      "goad-${pair[0]}-${pair[1]}" => { cidr = var.goad_agent_cidrs[pair[0]], port = pair[1] }
    },
  )

  network_security_group_id = oci_core_network_security_group.wazuh.id
  direction                 = "INGRESS"
  protocol                  = "6"
  source                    = each.value.cidr
  source_type               = "CIDR_BLOCK"

  tcp_options {
    destination_port_range {
      min = each.value.port
      max = each.value.port
    }
  }
}

resource "oci_core_network_security_group_security_rule" "agents_ssh" {
  network_security_group_id = oci_core_network_security_group.agents.id
  direction                 = "INGRESS"
  protocol                  = "6"
  source                    = local.bastion_cidr
  source_type               = "CIDR_BLOCK"

  tcp_options {
    destination_port_range {
      min = 22
      max = 22
    }
  }
}

resource "oci_core_network_security_group_security_rule" "egress" {
  for_each = {
    bastion = oci_core_network_security_group.bastion.id
    wazuh   = oci_core_network_security_group.wazuh.id
    agents  = oci_core_network_security_group.agents.id
  }

  network_security_group_id = each.value
  direction                 = "EGRESS"
  protocol                  = "all"
  destination               = "0.0.0.0/0"
  destination_type          = "CIDR_BLOCK"
}
