# ---------------------------------------------------------------------------
# Node pools
#
# Two pools, each pinned to a different POD subnet. This is where the lane
# separation becomes schedulable:
#
#   phi    : pods get VNICs in the SEALED subnet. GPU for in-tenancy vLLM.
#   egress : pods get VNICs in the egress subnet. CPU only.
#
# The pod_subnet_ids setting on each pool is the enforcement point. A pod
# on a phi node cannot obtain an address outside the sealed subnet.
# ---------------------------------------------------------------------------

data "oci_identity_availability_domains" "ads" {
  compartment_id = var.tenancy_ocid
}

data "oci_containerengine_node_pool_option" "main" {
  node_pool_option_id = "all"
}

locals {
  # Strip the leading "v" from e.g. v1.31.1 so it matches the image names.
  k8s_version_plain = replace(local.k8s_version, "v", "")

  # Non-GPU Oracle Linux 8 OKE image for the egress pool.
  node_image_id = [
    for src in data.oci_containerengine_node_pool_option.main.sources :
    src.image_id
    if length(regexall("Oracle-Linux-8", src.source_name)) > 0
    && length(regexall(local.k8s_version_plain, src.source_name)) > 0
    && length(regexall("GPU", src.source_name)) == 0
    && length(regexall("aarch64", src.source_name)) == 0
  ][0]

  # GPU-enabled Oracle Linux 8 OKE image for the PHI pool.
  gpu_image_id = [
    for src in data.oci_containerengine_node_pool_option.main.sources :
    src.image_id
    if length(regexall("Oracle-Linux-8", src.source_name)) > 0
    && length(regexall(local.k8s_version_plain, src.source_name)) > 0
    && length(regexall("GPU", src.source_name)) > 0
  ][0]
}

# --- PHI lane: GPU, sealed pod subnet ---------------------------------------
resource "oci_containerengine_node_pool" "phi" {
  cluster_id         = oci_containerengine_cluster.main.id
  compartment_id     = var.compartment_ocid
  name               = "${var.project_name}-np-phi"
  kubernetes_version = local.k8s_version
  node_shape         = "VM.GPU.A10.1"

  node_source_details {
    image_id                = local.gpu_image_id
    source_type             = "IMAGE"
    boot_volume_size_in_gbs = 200
  }

  node_config_details {
    size = 1

    placement_configs {
      availability_domain = data.oci_identity_availability_domains.ads.availability_domains[0].name
      subnet_id           = oci_core_subnet.nodes.id
    }

    node_pool_pod_network_option_details {
      cni_type          = "OCI_VCN_IP_NATIVE"
      pod_subnet_ids    = [oci_core_subnet.phi_pods.id]
      max_pods_per_node = 31
    }
  }

  initial_node_labels {
    key   = "phi-lane.oracle.com/lane"
    value = "sealed"
  }
}

# --- Egress lane: CPU, egress pod subnet ------------------------------------
resource "oci_containerengine_node_pool" "egress" {
  cluster_id         = oci_containerengine_cluster.main.id
  compartment_id     = var.compartment_ocid
  name               = "${var.project_name}-np-egress"
  kubernetes_version = local.k8s_version
  node_shape         = "VM.Standard.E4.Flex"

  node_shape_config {
    ocpus         = 2
    memory_in_gbs = 32
  }

  node_source_details {
    image_id                = local.node_image_id
    source_type             = "IMAGE"
    boot_volume_size_in_gbs = 100
  }

  node_config_details {
    size = 2

    placement_configs {
      availability_domain = data.oci_identity_availability_domains.ads.availability_domains[0].name
      subnet_id           = oci_core_subnet.nodes.id
    }

    node_pool_pod_network_option_details {
      cni_type          = "OCI_VCN_IP_NATIVE"
      pod_subnet_ids    = [oci_core_subnet.egress_pods.id]
      max_pods_per_node = 31
    }
  }

  initial_node_labels {
    key   = "phi-lane.oracle.com/lane"
    value = "egress"
  }
}
