variable "tenancy_ocid" {
  description = "Tenancy OCID. Also serves as the root compartment OCID."
  type        = string
}

variable "compartment_ocid" {
  description = "Compartment in which all resources are created."
  type        = string
}

variable "region" {
  description = "OCI region. Must offer VM.GPU.A10.1 for the sealed lane."
  type        = string
  default     = "us-ashburn-1"
}

variable "project_name" {
  description = "Name prefix applied to all resources."
  type        = string
  default     = "phi-lane"
}

variable "vcn_cidr" {
  description = "CIDR block for the VCN."
  type        = string
  default     = "10.0.0.0/16"
}

variable "k8s_node_subnet_cidr" {
  description = "Worker node subnet. Nodes for both lanes live here."
  type        = string
  default     = "10.0.1.0/24"
}

variable "phi_pod_subnet_cidr" {
  description = "Sealed pod subnet. Route table has no path to the internet."
  type        = string
  default     = "10.0.16.0/20"
}

variable "egress_pod_subnet_cidr" {
  description = "Egress-capable pod subnet. NAT gateway, NSG allow-list."
  type        = string
  default     = "10.0.32.0/20"
}

variable "api_endpoint_subnet_cidr" {
  description = "OKE control plane endpoint subnet."
  type        = string
  default     = "10.0.0.0/28"
}

variable "lb_subnet_cidr" {
  description = "Load balancer subnet fronting the gateway."
  type        = string
  default     = "10.0.2.0/24"
}
