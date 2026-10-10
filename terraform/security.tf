# ---------------------------------------------------------------------------
# Security lists
#
# OKE has hard networking prerequisites. Nodes must reach the control plane
# on 6443 (Kubernetes API) and 12250 (OKE node communication), and the
# control plane must reach the nodes. Without these rules nodes boot, the
# kubelet retries registration, and the node pool fails with a register
# timeout.
#
# IMPORTANT: these are security lists, which FILTER traffic. They are not
# the residency control. The residency control is the route table on the
# PHI pod subnet, which determines what destinations EXIST. A filter can be
# edited to allow something new; a missing route cannot be filtered around.
# ---------------------------------------------------------------------------

# --- API endpoint subnet ----------------------------------------------------
resource "oci_core_security_list" "api_endpoint" {
  compartment_id = var.compartment_ocid
  vcn_id         = oci_core_vcn.main.id
  display_name   = "${var.project_name}-sl-api"

  # Control plane to OCI services.
  egress_security_rules {
    destination      = data.oci_core_services.all_oci_services.services[0]["cidr_block"]
    destination_type = "SERVICE_CIDR_BLOCK"
    protocol         = "6"
    stateless        = false
  }

  # Control plane to worker nodes.
  egress_security_rules {
    destination      = var.k8s_node_subnet_cidr
    destination_type = "CIDR_BLOCK"
    protocol         = "6"
    stateless        = false
  }

  # Control plane to pods in both lanes.
  egress_security_rules {
    destination      = var.phi_pod_subnet_cidr
    destination_type = "CIDR_BLOCK"
    protocol         = "all"
    stateless        = false
  }

  egress_security_rules {
    destination      = var.egress_pod_subnet_cidr
    destination_type = "CIDR_BLOCK"
    protocol         = "all"
    stateless        = false
  }

  # Path discovery to nodes.
  egress_security_rules {
    destination      = var.k8s_node_subnet_cidr
    destination_type = "CIDR_BLOCK"
    protocol         = "1"
    stateless        = false

    icmp_options {
      type = 3
      code = 4
    }
  }

  # kubectl from anywhere (public endpoint).
  ingress_security_rules {
    source      = "0.0.0.0/0"
    source_type = "CIDR_BLOCK"
    protocol    = "6"
    stateless   = false

    tcp_options {
      min = 6443
      max = 6443
    }
  }

  # Nodes to control plane: Kubernetes API.
  ingress_security_rules {
    source      = var.k8s_node_subnet_cidr
    source_type = "CIDR_BLOCK"
    protocol    = "6"
    stateless   = false

    tcp_options {
      min = 6443
      max = 6443
    }
  }

  # Nodes to control plane: OKE node communication.
  ingress_security_rules {
    source      = var.k8s_node_subnet_cidr
    source_type = "CIDR_BLOCK"
    protocol    = "6"
    stateless   = false

    tcp_options {
      min = 12250
      max = 12250
    }
  }

  # Pods to control plane, both lanes.
  ingress_security_rules {
    source      = var.phi_pod_subnet_cidr
    source_type = "CIDR_BLOCK"
    protocol    = "6"
    stateless   = false

    tcp_options {
      min = 6443
      max = 6443
    }
  }

  ingress_security_rules {
    source      = var.phi_pod_subnet_cidr
    source_type = "CIDR_BLOCK"
    protocol    = "6"
    stateless   = false

    tcp_options {
      min = 12250
      max = 12250
    }
  }

  ingress_security_rules {
    source      = var.egress_pod_subnet_cidr
    source_type = "CIDR_BLOCK"
    protocol    = "6"
    stateless   = false

    tcp_options {
      min = 6443
      max = 6443
    }
  }

  ingress_security_rules {
    source      = var.egress_pod_subnet_cidr
    source_type = "CIDR_BLOCK"
    protocol    = "6"
    stateless   = false

    tcp_options {
      min = 12250
      max = 12250
    }
  }

  # Path discovery from nodes.
  ingress_security_rules {
    source      = var.k8s_node_subnet_cidr
    source_type = "CIDR_BLOCK"
    protocol    = "1"
    stateless   = false

    icmp_options {
      type = 3
      code = 4
    }
  }
}

# --- Worker node subnet -----------------------------------------------------
resource "oci_core_security_list" "nodes" {
  compartment_id = var.compartment_ocid
  vcn_id         = oci_core_vcn.main.id
  display_name   = "${var.project_name}-sl-nodes"

  # Nodes need broad egress: control plane, image registries, OCI services.
  egress_security_rules {
    destination      = "0.0.0.0/0"
    destination_type = "CIDR_BLOCK"
    protocol         = "all"
    stateless        = false
  }

  # Node to node.
  ingress_security_rules {
    source      = var.k8s_node_subnet_cidr
    source_type = "CIDR_BLOCK"
    protocol    = "all"
    stateless   = false
  }

  # Control plane to nodes.
  ingress_security_rules {
    source      = var.api_endpoint_subnet_cidr
    source_type = "CIDR_BLOCK"
    protocol    = "6"
    stateless   = false
  }

  # Pods to nodes, both lanes.
  ingress_security_rules {
    source      = var.phi_pod_subnet_cidr
    source_type = "CIDR_BLOCK"
    protocol    = "all"
    stateless   = false
  }

  ingress_security_rules {
    source      = var.egress_pod_subnet_cidr
    source_type = "CIDR_BLOCK"
    protocol    = "all"
    stateless   = false
  }

  # Load balancer health checks and traffic.
  ingress_security_rules {
    source      = var.lb_subnet_cidr
    source_type = "CIDR_BLOCK"
    protocol    = "6"
    stateless   = false
  }

  # Path discovery.
  ingress_security_rules {
    source      = "0.0.0.0/0"
    source_type = "CIDR_BLOCK"
    protocol    = "1"
    stateless   = false

    icmp_options {
      type = 3
      code = 4
    }
  }
}

# --- PHI pod subnet ---------------------------------------------------------
#
# Note what this does and does not do. The egress rule below is permissive:
# it allows outbound TCP anywhere. That is deliberate, and it is the point
# of the architecture. Even with a wide-open filter, a PHI-lane pod cannot
# reach the internet, because the SEALED ROUTE TABLE provides no path there.
#
# The filter is permissive. The topology is not. That is what "substrate
# enforcement" means.
# ---------------------------------------------------------------------------
resource "oci_core_security_list" "phi_pods" {
  compartment_id = var.compartment_ocid
  vcn_id         = oci_core_vcn.main.id
  display_name   = "${var.project_name}-sl-phi-pods"

  egress_security_rules {
    destination      = "0.0.0.0/0"
    destination_type = "CIDR_BLOCK"
    protocol         = "all"
    stateless        = false
  }

  ingress_security_rules {
    source      = var.phi_pod_subnet_cidr
    source_type = "CIDR_BLOCK"
    protocol    = "all"
    stateless   = false
  }

  ingress_security_rules {
    source      = var.k8s_node_subnet_cidr
    source_type = "CIDR_BLOCK"
    protocol    = "all"
    stateless   = false
  }

  ingress_security_rules {
    source      = var.api_endpoint_subnet_cidr
    source_type = "CIDR_BLOCK"
    protocol    = "6"
    stateless   = false
  }

  ingress_security_rules {
    source      = var.lb_subnet_cidr
    source_type = "CIDR_BLOCK"
    protocol    = "6"
    stateless   = false
  }
}

# --- Egress lane pod subnet -------------------------------------------------
resource "oci_core_security_list" "egress_pods" {
  compartment_id = var.compartment_ocid
  vcn_id         = oci_core_vcn.main.id
  display_name   = "${var.project_name}-sl-egress-pods"

  egress_security_rules {
    destination      = "0.0.0.0/0"
    destination_type = "CIDR_BLOCK"
    protocol         = "all"
    stateless        = false
  }

  ingress_security_rules {
    source      = var.egress_pod_subnet_cidr
    source_type = "CIDR_BLOCK"
    protocol    = "all"
    stateless   = false
  }

  ingress_security_rules {
    source      = var.k8s_node_subnet_cidr
    source_type = "CIDR_BLOCK"
    protocol    = "all"
    stateless   = false
  }

  ingress_security_rules {
    source      = var.api_endpoint_subnet_cidr
    source_type = "CIDR_BLOCK"
    protocol    = "6"
    stateless   = false
  }

  ingress_security_rules {
    source      = var.lb_subnet_cidr
    source_type = "CIDR_BLOCK"
    protocol    = "6"
    stateless   = false
  }
}

# --- Load balancer subnet ---------------------------------------------------
resource "oci_core_security_list" "lb" {
  compartment_id = var.compartment_ocid
  vcn_id         = oci_core_vcn.main.id
  display_name   = "${var.project_name}-sl-lb"

  egress_security_rules {
    destination      = "0.0.0.0/0"
    destination_type = "CIDR_BLOCK"
    protocol         = "all"
    stateless        = false
  }

  ingress_security_rules {
    source      = "0.0.0.0/0"
    source_type = "CIDR_BLOCK"
    protocol    = "6"
    stateless   = false

    tcp_options {
      min = 80
      max = 80
    }
  }

  ingress_security_rules {
    source      = "0.0.0.0/0"
    source_type = "CIDR_BLOCK"
    protocol    = "6"
    stateless   = false

    tcp_options {
      min = 443
      max = 443
    }
  }
}
