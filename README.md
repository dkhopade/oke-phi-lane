# OKE PHI Lane

**Network-enforced PHI residency for LLM inference on Kubernetes.**

A reference implementation of a data-class boundary that is enforced by network
topology rather than by application convention. Protected health information
cannot reach an external model provider because no route exists, not because
code declined to send it.

## The problem

Kubernetes has no primitive for data-class boundaries.

`NetworkPolicy` expresses which pod may talk to which pod. It cannot express
which *class of data* may leave the tenancy. In most healthcare AI platforms
that decision lives in application code, in a model endpoint a developer chose.
That is a convention, not a control. One bad merge makes it a reportable breach.

## The approach

Enforcement is layered, and each layer is independently sufficient to stop the
violation. The lower the layer, the harder it is for the workload to bypass.

| Layer | Mechanism | Can the workload bypass it? |
|---|---|---|
| Classification | Envoy external processor at the gateway | No. Runs on the trust boundary, not in the caller. |
| Routing | Gateway API Inference Extension pools | No. Declarative, admission-controlled. |
| Cluster network | NetworkPolicy | Advisory. Enforced by the cluster under audit. |
| Credential | Workload identity scoped per lane | No. The PHI lane cannot obtain the external key. |
| Substrate | Pod subnet route table with no internet path | No. There is nowhere for the packet to go. |
| Evidence | VCN flow logs, outside the cluster | No. Written by the fabric, not the application. |

The design principle: **any control the workload can bypass is not a control.**

## Architecture

See [docs/architecture.md](docs/architecture.md).

## Components

| Function | Project / primitive |
|---|---|
| Ingress and routing | Gateway API, Envoy Gateway |
| Inference routing | Gateway API Inference Extension |
| PHI classification | Microsoft Presidio, via Envoy ext_proc |
| In-tenancy inference | vLLM on GPU node pool |
| Deploy-time guardrails | Kyverno |
| Telemetry | OpenTelemetry, Prometheus |
| Lane isolation | OKE pod subnets, route tables, NSGs |
| Credential scoping | OKE workload identity |
| Audit evidence | VCN flow logs, OCI Audit |

## Threat model

Documented in [docs/threat-model.md](docs/threat-model.md), including what this
design does **not** protect against.

The most instructive finding from the first implementation: callers were trusted
to declare their own data classification. A caller that can assert
`dataclass: non-phi` about PHI defeats every layer above the substrate. Any
classification performed by the caller is a classification the caller can lie
about.

## Status

Active development. This repository accompanies a conference session on
network-enforced data residency for regulated AI workloads.

| Component | State |
|---|---|
| Architecture and threat model | Drafted |
| Network topology (Terraform) | In progress |
| Gateway and routing manifests | Planned |
| Classifier service | Planned |
| Demo scenarios | Planned |

## Layout

    terraform/    two-lane network topology, node pools
    manifests/    Gateway, InferencePool, ext_proc, Kyverno policies
    classifier/   Presidio-based external processor
    demo/         scenario harness
    docs/         architecture, threat model
    FINDINGS.md   what broke, and why

## License

Apache 2.0
