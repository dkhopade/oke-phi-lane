# ---------------------------------------------------------------------------
# VCN
# ---------------------------------------------------------------------------

resource "oci_core_vcn" "main" {
  compartment_id = var.compartment_ocid
  cidr_blocks    = [var.vcn_cidr]
  display_name   = "${var.project_name}-vcn"
  dns_label      = replace(var.project_name, "-", "")
}

# ---------------------------------------------------------------------------
# Gateways
#
# Three gateways, and which subnets may reach each one is the entire
# enforcement model:
#
#   internet_gateway : inbound to the load balancer only
#   nat_gateway      : outbound for the EGRESS lane only
#   service_gateway  : OCI services without traversing the internet.
#                      This is the only outbound path the PHI lane gets.
# ---------------------------------------------------------------------------

resource "oci_core_internet_gateway" "main" {
  compartment_id = var.compartment_ocid
  vcn_id         = oci_core_vcn.main.id
  display_name   = "${var.project_name}-igw"
  enabled        = true
}

resource "oci_core_nat_gateway" "main" {
  compartment_id = var.compartment_ocid
  vcn_id         = oci_core_vcn.main.id
  display_name   = "${var.project_name}-natgw"
}

data "oci_core_services" "all_oci_services" {
  filter {
    name   = "name"
    values = ["All .* Services In Oracle Services Network"]
    regex  = true
  }
}

resource "oci_core_service_gateway" "main" {
  compartment_id = var.compartment_ocid
  vcn_id         = oci_core_vcn.main.id
  display_name   = "${var.project_name}-sgw"

  services {
    service_id = data.oci_core_services.all_oci_services.services[0]["id"]
  }
}
