# Network topology

Two-lane VCN layout: sealed PHI pod subnet with no internet route, and an
egress-capable subnet with an NSG allow-list to approved provider endpoints.
Includes GPU node pool placement and the IAM dynamic group backing workload
identity for the egress lane.

Status: in progress.
