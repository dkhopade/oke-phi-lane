# ---------------------------------------------------------------------------
# Route tables
#
# This file IS the compliance boundary.
#
# A route table is not a filter. It is the set of destinations that exist.
# The PHI pod subnet has no route to 0.0.0.0/0 by any path. A packet bound
# for an external model provider is not denied; it has nowhere to go.
# ---------------------------------------------------------------------------

# Public: load balancer subnet. Inbound clinical traffic arrives here.
resource "oci_core_route_table" "public" {
  compartment_id = var.compartment_ocid
  vcn_id         = oci_core_vcn.main.id
  display_name   = "${var.project_name}-rt-public"

  route_rules {
    destination       = "0.0.0.0/0"
    destination_type  = "CIDR_BLOCK"
    network_entity_id = oci_core_internet_gateway.main.id
  }
}

# Private: worker nodes and the OKE control plane endpoint.
# Needs NAT to pull images and reach the OKE API.
resource "oci_core_route_table" "private" {
  compartment_id = var.compartment_ocid
  vcn_id         = oci_core_vcn.main.id
  display_name   = "${var.project_name}-rt-private"

  route_rules {
    destination       = "0.0.0.0/0"
    destination_type  = "CIDR_BLOCK"
    network_entity_id = oci_core_nat_gateway.main.id
  }

  route_rules {
    destination       = data.oci_core_services.all_oci_services.services[0]["cidr_block"]
    destination_type  = "SERVICE_CIDR_BLOCK"
    network_entity_id = oci_core_service_gateway.main.id
  }
}

# ---------------------------------------------------------------------------
# SEALED: the PHI pod subnet.
#
# One rule. OCI services only, over the Oracle backbone.
#
# There is deliberately NO 0.0.0.0/0 rule here. Adding one would end the
# guarantee this architecture makes. If you are reading this file wondering
# why PHI-lane pods cannot reach the internet: that is the feature.
# ---------------------------------------------------------------------------
resource "oci_core_route_table" "phi_sealed" {
  compartment_id = var.compartment_ocid
  vcn_id         = oci_core_vcn.main.id
  display_name   = "${var.project_name}-rt-phi-sealed"

  route_rules {
    destination       = data.oci_core_services.all_oci_services.services[0]["cidr_block"]
    destination_type  = "SERVICE_CIDR_BLOCK"
    network_entity_id = oci_core_service_gateway.main.id
  }
}

# Egress lane pod subnet: NAT for approved external providers.
# NSGs narrow this to specific endpoints; the route only makes egress possible.
resource "oci_core_route_table" "egress_lane" {
  compartment_id = var.compartment_ocid
  vcn_id         = oci_core_vcn.main.id
  display_name   = "${var.project_name}-rt-egress-lane"

  route_rules {
    destination       = "0.0.0.0/0"
    destination_type  = "CIDR_BLOCK"
    network_entity_id = oci_core_nat_gateway.main.id
  }

  route_rules {
    destination       = data.oci_core_services.all_oci_services.services[0]["cidr_block"]
    destination_type  = "SERVICE_CIDR_BLOCK"
    network_entity_id = oci_core_service_gateway.main.id
  }
}
