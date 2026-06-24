resource "oci_core_vcn" "this" {
  compartment_id = var.compartment_id
  cidr_block     = "10.20.0.0/16"
  display_name   = "${var.project_name}-vcn"
  dns_label      = "wazuhlab"
  freeform_tags  = var.freeform_tags
  defined_tags   = var.defined_tags
}

resource "oci_core_internet_gateway" "this" {
  compartment_id = var.compartment_id
  vcn_id         = oci_core_vcn.this.id
  display_name   = "${var.project_name}-igw"
  enabled        = true
  freeform_tags  = var.freeform_tags
  defined_tags   = var.defined_tags
}

resource "oci_core_nat_gateway" "this" {
  compartment_id = var.compartment_id
  vcn_id         = oci_core_vcn.this.id
  display_name   = "${var.project_name}-nat"
  freeform_tags  = var.freeform_tags
  defined_tags   = var.defined_tags
}

resource "oci_core_route_table" "public" {
  compartment_id = var.compartment_id
  vcn_id         = oci_core_vcn.this.id
  display_name   = "${var.project_name}-public-rt"
  freeform_tags  = var.freeform_tags
  defined_tags   = var.defined_tags

  route_rules {
    destination       = "0.0.0.0/0"
    destination_type  = "CIDR_BLOCK"
    network_entity_id = oci_core_internet_gateway.this.id
  }
}

resource "oci_core_route_table" "private" {
  compartment_id = var.compartment_id
  vcn_id         = oci_core_vcn.this.id
  display_name   = "${var.project_name}-private-rt"
  freeform_tags  = var.freeform_tags
  defined_tags   = var.defined_tags

  route_rules {
    destination       = "0.0.0.0/0"
    destination_type  = "CIDR_BLOCK"
    network_entity_id = oci_core_nat_gateway.this.id
  }
}

resource "oci_core_security_list" "public" {
  compartment_id = var.compartment_id
  vcn_id         = oci_core_vcn.this.id
  display_name   = "${var.project_name}-public-sl"
  freeform_tags  = var.freeform_tags
  defined_tags   = var.defined_tags

  ingress_security_rules {
    protocol = "6"
    source   = var.operator_cidr

    tcp_options {
      min = 22
      max = 22
    }
  }

  egress_security_rules {
    protocol    = "all"
    destination = "0.0.0.0/0"
  }
}

resource "oci_core_security_list" "private" {
  compartment_id = var.compartment_id
  vcn_id         = oci_core_vcn.this.id
  display_name   = "${var.project_name}-private-sl"
  freeform_tags  = var.freeform_tags
  defined_tags   = var.defined_tags

  ingress_security_rules {
    protocol = "all"
    source   = "10.20.0.0/16"
  }

  egress_security_rules {
    protocol    = "all"
    destination = "0.0.0.0/0"
  }
}

resource "oci_core_subnet" "public" {
  compartment_id             = var.compartment_id
  vcn_id                     = oci_core_vcn.this.id
  cidr_block                 = "10.20.10.0/24"
  display_name               = "${var.project_name}-public"
  prohibit_public_ip_on_vnic = false
  route_table_id             = oci_core_route_table.public.id
  security_list_ids          = [oci_core_security_list.public.id]
  freeform_tags              = var.freeform_tags
  defined_tags               = var.defined_tags
}

resource "oci_core_subnet" "private" {
  compartment_id             = var.compartment_id
  vcn_id                     = oci_core_vcn.this.id
  cidr_block                 = "10.20.20.0/24"
  display_name               = "${var.project_name}-private"
  prohibit_public_ip_on_vnic = true
  route_table_id             = oci_core_route_table.private.id
  security_list_ids          = [oci_core_security_list.private.id]
  freeform_tags              = var.freeform_tags
  defined_tags               = var.defined_tags
}

resource "oci_core_network_security_group" "bastion" {
  compartment_id = var.compartment_id
  vcn_id         = oci_core_vcn.this.id
  display_name   = "${var.project_name}-bastion-nsg"
  freeform_tags  = var.freeform_tags
  defined_tags   = var.defined_tags
}

resource "oci_core_network_security_group" "wazuh" {
  compartment_id = var.compartment_id
  vcn_id         = oci_core_vcn.this.id
  display_name   = "${var.project_name}-wazuh-nsg"
  freeform_tags  = var.freeform_tags
  defined_tags   = var.defined_tags
}

resource "oci_core_network_security_group" "agent" {
  compartment_id = var.compartment_id
  vcn_id         = oci_core_vcn.this.id
  display_name   = "${var.project_name}-agent-nsg"
  freeform_tags  = var.freeform_tags
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

resource "oci_core_network_security_group_security_rule" "wazuh_from_vcn" {
  for_each = {
    ssh       = 22
    dashboard = 443
    enroll    = 1515
    events    = 1514
    api       = 55000
  }

  network_security_group_id = oci_core_network_security_group.wazuh.id
  direction                 = "INGRESS"
  protocol                  = "6"
  source                    = "10.20.0.0/16"
  source_type               = "CIDR_BLOCK"

  tcp_options {
    destination_port_range {
      min = each.value
      max = each.value
    }
  }
}

resource "oci_core_network_security_group_security_rule" "private_egress" {
  for_each = {
    bastion = oci_core_network_security_group.bastion.id
    wazuh   = oci_core_network_security_group.wazuh.id
    agent   = oci_core_network_security_group.agent.id
  }

  network_security_group_id = each.value
  direction                 = "EGRESS"
  protocol                  = "all"
  destination               = "0.0.0.0/0"
  destination_type          = "CIDR_BLOCK"
}
