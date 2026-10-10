# ---------------------------------------------------------------------------
# OKE cluster
#
# VCN-native pod networking is the architectural requirement here, not a
# preference. With the overlay CNI, pods inherit the node's network identity
# and egress path, which would force one node pool per lane. With VCN-native
# pods, each pod gets its own VNIC in a pod subnet of its own, so the lane
# is a property of the POD rather than the node it happens to land on.
# ---------------------------------------------------------------------------

data "oci_containerengine_cluster_option" "main" {
  cluster_option_id = "all"
}

locals {
  k8s_version = reverse(sort(data.oci_containerengine_cluster_option.main.kubernetes_versions))[0]
}

resource "oci_containerengine_cluster" "main" {
  compartment_id     = var.compartment_ocid
  name               = "${var.project_name}-oke"
  kubernetes_version = local.k8s_version
  vcn_id             = oci_core_vcn.main.id
  type               = "ENHANCED_CLUSTER"

  cluster_pod_network_options {
    cni_type = "OCI_VCN_IP_NATIVE"
  }

  endpoint_config {
    subnet_id            = oci_core_subnet.api_endpoint.id
    is_public_ip_enabled = true
  }

  options {
    service_lb_subnet_ids = [oci_core_subnet.lb.id]

    kubernetes_network_config {
      pods_cidr     = "10.244.0.0/16"
      services_cidr = "10.96.0.0/16"
    }

    add_ons {
      is_kubernetes_dashboard_enabled = false
      is_tiller_enabled               = false
    }
  }
}

output "cluster_id" {
  value       = oci_containerengine_cluster.main.id
  description = "OKE cluster OCID"
}

output "kubernetes_version" {
  value       = local.k8s_version
  description = "Kubernetes version selected for the cluster"
}
