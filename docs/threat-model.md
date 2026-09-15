# Threat model

## What is being protected

Protected health information present in inference request bodies, and the
evidence needed to demonstrate that it did not leave the tenancy.

The claim this design makes is narrow and deliberate: **PHI cannot reach a
third-party model provider.** It is not a claim that PHI is safe, that the
platform is HIPAA compliant, or that all exfiltration paths are closed.

## Primary adversary

Not an attacker. The dominant real-world threat is a competent developer under
deadline pressure who selects the wrong model endpoint, and a review process
that does not catch it. Most PHI incidents in AI platforms are configuration
outcomes rather than intrusions.

A compromised workload inside the cluster is the secondary adversary, and the
substrate layer is what makes that case survivable.

## Trust boundaries

| Boundary | Trusted | Not trusted |
|---|---|---|
| Gateway | ext_proc classifier decision | Caller-supplied classification |
| Cluster | Admission policy at deploy time | Running workload behavior |
| Tenancy | VCN route tables, NSGs | Anything inside a pod |
| Evidence | VCN flow logs, OCI Audit | Application-emitted audit logs |

## Scenarios

| # | Scenario | Caught by | Holds? |
|---|---|---|---|
| 1 | Developer hardcodes an external provider endpoint for PHI traffic | Substrate. No route exists. | Yes |
| 2 | Caller asserts its own data class to force the external lane | Classification moved to the gateway | Yes |
| 3 | Classifier fails to recognize PHI in the payload | Nothing | **No** |
| 4 | Deployment places a PHI workload on an egress-capable node | Kyverno at admission | Yes |
| 5 | PHI-lane pod attempts to read the external provider credential | Workload identity scoping | Yes |
| 6 | Compromised PHI-lane pod writes PHI to in-tenancy object storage | Nothing residency-related | Out of scope |
| 7 | Route table or NSG modified outside the cluster | Nothing at runtime | **No** |
| 8 | PHI appears in traces, logs, or metrics leaving the tenancy | Nothing by default | **No** |

## The three that do not hold

**Classifier false negatives (3).** Presidio is rule-based and statistical. A
missed identifier means PHI is routed to the external lane by a correctly
functioning system. Every layer below classification is reachable only because
classification said it was safe to be there. This is the single largest residual
risk in the design. Partial mitigation is posture: treat unclassifiable or
low-confidence payloads as PHI and route them to the sealed lane, so the failure
mode is a cost increase rather than a disclosure. That converts an unbounded
risk into a bounded one. It does not eliminate it.

**Configuration drift (7).** The cluster has no awareness of its own network
topology. If a route table gains a NAT gateway through a console change or an
out-of-band Terraform apply, the substrate layer silently stops existing and
nothing in Kubernetes reports it. Detection belongs in OCI Audit alarms and
drift checks, not in the cluster. This is the failure that would be discovered
during an audit rather than during operations.

**Telemetry as an exfiltration path (8).** Observability is usually treated as
orthogonal to data boundaries, and it is not. An OpenTelemetry span carrying a
request body, a Prometheus label carrying a patient identifier, or a debug log
shipped to a SaaS backend moves PHI out of the tenancy through a channel none of
the enforcement layers inspect. Telemetry egress deserves the same lane
treatment as inference egress and does not receive it here.

## Explicitly out of scope

- Whether the external provider handles non-PHI data appropriately
- Model memorization and training-data leakage
- Prompt injection causing an application to embed PHI it should not have sent
- Access control within the tenancy, as distinct from residency across it
- An insider with IAM write permission on the VCN, who can remove the substrate

## Design principle

Any control the workload can bypass is not a control. The layers above the
substrate reduce the frequency of violations. Only the substrate changes what
is possible.
