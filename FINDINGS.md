# Findings

What broke during this build, and what each failure taught. Recorded because the
failures were more instructive than the successes, and because the next person
building this will hit most of them.

---

## 1. Node pools fail to register with no useful error

**Symptom.** Both node pools failed after 28 minutes with
`1 nodes(s) register timeout`. The nodes booted. The kubelet started. Nothing
in the OKE console or the work request said why.

**Cause.** The VCN's default security list does not carry OKE's networking
prerequisites. Worker nodes must reach the control plane on **6443**
(Kubernetes API) and **12250** (OKE node communication), and the control plane
must reach the nodes. In this topology the API endpoint lives in its own subnet,
so that traffic crosses a subnet boundary and is evaluated by security lists.
Nothing permitted it.

**Fix.** Five explicit security lists, one per subnet, with the 6443/12250 rules
in both directions plus ICMP type 3 code 4 for path MTU discovery.

**What it cost.** Two failed applies, roughly an hour, and one A10 allocated for
28 minutes doing nothing.

**The lesson.** The timeout is generous because legitimate GPU node boots are
slow. That generosity means a networking misconfiguration and a slow boot look
identical for the first 25 minutes. Build the security rules before the cluster,
not after the first failure.

---

## 2. CRI-O refuses unqualified image names

**Symptom.** Pods stuck in `ImageInspectError`. Both probe pods, identical
failure.

```
Failed to inspect image "": short name mode is enforcing,
but image name curlimages/curl:8.11.1 returns ambiguous list
```

**Cause.** OKE's Oracle Linux nodes run CRI-O with `short-name-mode = enforcing`.
An image name without a registry prefix could resolve to Docker Hub, OCIR, Quay
or anything else configured, so CRI-O refuses to guess rather than picking one.

**Fix.** Fully qualify: `docker.io/curlimages/curl:8.11.1`.

**The lesson.** This is a security property, not an inconvenience, and it belongs
in a PHI context. An image silently pulled from an unintended registry is exactly
the kind of failure that should be loud. The dangerous failure is the silent one;
CRI-O chose correctly here.

---

## 3. DNS from the sealed lane is nondeterministic

**Symptom.** The first exfiltration test from the PHI lane returned
`curl: (6) Could not resolve host` rather than the expected connection timeout.

**Cause.** The pod queries CoreDNS, which must forward external queries upstream.
CoreDNS runs as several replicas spread across nodes. A replica on an egress-lane
node can reach an upstream resolver; a replica on the sealed node cannot. Which
answer you get depends on which replica fields the query.

**Why it matters beyond the demo.** This is nondeterministic behavior in a
compliance-critical path. A sealed-lane workload may resolve external names
sometimes and not others, with no signal distinguishing the two cases.

**Fix for the demo.** Test against a raw IP, removing DNS from the path entirely.
A connection timeout proves the route is absent; a DNS failure only proves the
name did not resolve, which a reviewer can dismiss as misconfiguration.

**Fix for production.** Pin CoreDNS replicas away from the sealed lane, or give
the sealed lane its own resolver with an explicit, auditable forwarding policy.
Not yet implemented here.

---

## 4. `prohibit_public_ip_on_vnic` is immutable

**Symptom.** Cluster creation rejected with
`Invalid subnetId: must be a public subnet if public ip enabled`. The fix —
flipping the API endpoint subnet to allow public IPs — produced a plan with
`# forces replacement` rather than an in-place update.

**Cause.** That attribute cannot be changed on an existing OCI subnet.
`security_list_ids` and `route_table_id` can; this one cannot.

**Why it was survivable.** Nothing had been deployed into that subnet yet. The
same edit after the cluster existed would have required destroying a subnet
holding the control plane endpoint.

**The lesson.** Decide whether the control plane endpoint is public before
creating the cluster. Worth knowing which subnet attributes are immutable before
planning any change to a live one.

---

## 5. A verification command that lied

**Symptom.** A check intended to confirm the sealed route table had no default
route reported one:

```bash
grep -A 20 'phi_sealed' terraform/routing.tf | grep -c '0.0.0.0/0'   # returned 1
```

**Cause.** `grep -A` takes a fixed line count and knows nothing about block
boundaries. The 20-line window ran past the end of the sealed resource and into
the next one, which legitimately contains a default route.

**Why this is the most important finding here.** The check produced a false
positive on the single most important safety property in the architecture. A
check scoped slightly wrong can just as easily report clean when something is
broken, and a check that cries wolf trains you to ignore it.

**The lesson, and why the demo is built the way it is.** Verify the property
empirically rather than by reading configuration. The demo watches a packet fail
to leave. That cannot be fooled by a bad grep.

---

## 6. The sealed lane's firewall permits everything

Not a defect. Recorded because it reads like one.

The security list attached to the PHI pod subnet allows all outbound TCP to
`0.0.0.0/0`. The lane is sealed anyway, because the route table supplies no next
hop. Someone auditing this looking for the rule that stops PHI leaving will not
find one.

That is the architecture working as intended: the filter is permissive and the
topology is not. A filter can be widened by anyone with network write access. A
missing route cannot be filtered around.

---

## Measured result

Two pods from one manifest, same image, same namespace, no NetworkPolicy on
either, both subnets permitting all outbound TCP. Connection to a raw IP, so DNS
plays no part.

```
egress lane   →  1.1.1.1   HTTP 301 in 0.091893s
PHI lane      →  1.1.1.1   timeout at 10.002612s   (curl exit 28)
```

Nothing denied the second request. No policy evaluated and rejected it, no
firewall logged a violation, and no audit entry records a blocked attempt —
because nothing was blocked.
