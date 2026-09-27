# ---------------------------------------------------------------------------
# Subnets
#
# Each subnet is bound to exactly one route table. That binding is what
# turns the routing decisions in routing.tf into a property of anything
# scheduled there.
# ---------------------------------------------------------------------------

# OKE control plane endpoint.
resource "oci_core_subnet" "api_endpoint" {
  compartment_id             = var.compartment_ocid
  vcn_id                     = oci_core_vcn.main.id
  cidr_block                 = var.api_endpoint_subnet_cidr
  display_name               = "${var.project_name}-subnet-api"
  dns_label                  = "api"
  route_table_id             = oci_core_route_table.private.id
  prohibit_public_ip_on_vnic = true
}

# Load balancer fronting the gateway. Public.
resource "oci_core_subnet" "lb" {
  compartment_id             = var.compartment_ocid
  vcn_id                     = oci_core_vcn.main.id
  cidr_block                 = var.lb_subnet_cidr
  display_name               = "${var.project_name}-subnet-lb"
  dns_label                  = "lb"
  route_table_id             = oci_core_route_table.public.id
  prohibit_public_ip_on_vnic = false
}

# Worker nodes for both lanes. Nodes need NAT to join the cluster and
# pull images. Lane separation happens at the POD subnet, not here.
resource "oci_core_subnet" "nodes" {
  compartment_id             = var.compartment_ocid
  vcn_id                     = oci_core_vcn.main.id
  cidr_block                 = var.k8s_node_subnet_cidr
  display_name               = "${var.project_name}-subnet-nodes"
  dns_label                  = "nodes"
  route_table_id             = oci_core_route_table.private.id
  prohibit_public_ip_on_vnic = true
}

# ---------------------------------------------------------------------------
# SEALED PHI pod subnet.
#
# Bound to the sealed route table. Every pod scheduled here receives a VCN
# IP from this subnet and inherits its routing. There is no path to the
# internet from this address space.
# ---------------------------------------------------------------------------
resource "oci_core_subnet" "phi_pods" {
  compartment_id             = var.compartment_ocid
  vcn_id                     = oci_core_vcn.main.id
  cidr_block                 = var.phi_pod_subnet_cidr
  display_name               = "${var.project_name}-subnet-phi-pods"
  dns_label                  = "phipods"
  route_table_id             = oci_core_route_table.phi_sealed.id
  prohibit_public_ip_on_vnic = true
}

# Egress lane pod subnet. NAT-capable, narrowed by NSG.
resource "oci_core_subnet" "egress_pods" {
  compartment_id             = var.compartment_ocid
  vcn_id                     = oci_core_vcn.main.id
  cidr_block                 = var.egress_pod_subnet_cidr
  display_name               = "${var.project_name}-subnet-egress-pods"
  dns_label                  = "egresspods"
  route_table_id             = oci_core_route_table.egress_lane.id
  prohibit_public_ip_on_vnic = true
}
