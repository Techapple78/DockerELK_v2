# Security Policy and Audit

## Supported deployment paths

| Deployment | Status | Security support |
| --- | --- | --- |
| K3s, ECK 3.4.0, Elastic Stack 9.4.2 | Current lab platform | Supported for this repository |
| Docker Compose, Ubuntu 16.04, Elastic Stack 6.x | Legacy migration source | Unsupported and must not be exposed |

The Kubernetes deployment is a laboratory profile. It is not a hardened,
high-availability production baseline.

## Reporting a vulnerability

Do not open a public issue containing credentials, exploit details, internal
addresses, kubeconfig data, Terraform state, or other sensitive evidence.

Preferred reporting process:

1. Use GitHub private vulnerability reporting or a private Security Advisory
   for `Techapple78/DockerELK_v2`.
2. Include the affected revision, component, reproduction steps, impact, and a
   proposed mitigation when available.
3. Remove secrets and personal infrastructure values from screenshots and
   logs.
4. Allow the maintainer time to reproduce, remediate, and publish a coordinated
   disclosure.

## Audit summary

Audit date: 2026-06-24

Audited revision: `f1c8efaca4699a0fffde5858d6a9d2ce1a469cdd`

Scope:

- Git history and tracked files;
- Dockerfiles and Docker Compose;
- Terraform and cloud-init;
- Kubernetes, ECK, Argo CD, and effective pod settings;
- deployed Elastic Stack container images;
- GitHub repository security settings.

Tools:

- Gitleaks 8.30.1;
- Trivy 0.71.2;
- `kubectl` API and RBAC inspection;
- GitHub REST API;
- manual configuration review.

Overall assessment: **high risk for the legacy Docker path** and **medium-high
risk for the current K3s lab until network isolation, image updates, and
credential scoping are completed**.

## Positive controls

- ECK provides TLS and authentication between Elasticsearch, Kibana, and
  Logstash.
- Elasticsearch is not exposed outside the cluster.
- Terraform variables, state, plans, kubeconfig, and private keys are ignored
  by Git.
- Gitleaks scanned 15 commits and found no secrets.
- GitHub secret scanning and push protection are enabled.
- Argo CD tracks a specific branch and the deployed application is
  `Synced/Healthy`.
- Versions are pinned for K3s, ECK, Argo CD, and Elastic Stack.
- Effective Elasticsearch and Kibana containers drop all Linux capabilities,
  deny privilege escalation, and use read-only root filesystems.

## Findings

| ID | Severity | Finding | Affected area | Recommended action |
| --- | --- | --- | --- | --- |
| SEC-001 | Critical | Legacy Ubuntu 16.04 and Elastic 6.x stack is unsupported and exposes unauthenticated plaintext services | `Elastic/`, `Kibana/`, `Logstash/`, `docker-compose.yml` | Retire or isolate the legacy deployment; never expose it outside a disposable migration network |
| SEC-002 | High | Trivy found one critical and multiple high-severity package vulnerabilities in current Elastic 9.4.2 images | Kubernetes Elastic images | Upgrade to a vendor release containing fixes after compatibility testing; review Elastic advisories and VEX |
| SEC-003 | High | Kibana and Logstash are exposed as NodePorts on every K3s node | `kubernetes/base/kibana.yaml`, `kubernetes/base/logstash.yaml` | Replace NodePorts with an authenticated ingress, firewall allowlist, or local port-forward only |
| SEC-004 | High | The `dockerelk` namespace has no NetworkPolicy | Kubernetes cluster | Add default-deny ingress and egress, then allow only required DNS, ECK, Kibana, Logstash, and Elasticsearch flows |
| SEC-005 | High | Logstash lacks an effective restricted container security context | `kubernetes/base/logstash.yaml` | Enforce non-root execution, no privilege escalation, dropped capabilities, seccomp, and a read-only root filesystem where compatible |
| SEC-006 | High | The administrator kubeconfig has unrestricted cluster-admin permissions | Operator workstation | Create least-privilege service accounts and separate read-only, deployer, and break-glass kubeconfigs |
| SEC-007 | High | Docker images run as root and use insecure package build patterns | Legacy Dockerfiles | Replace custom Ubuntu images with supported vendor images, non-root users, deterministic package installation, and health checks |
| SEC-008 | Medium | K3s is installed by downloading and executing a remote script without checksum or signature verification | cloud-init templates | Mirror and verify the installer or use a pinned, signed package or artifact with a validated digest |
| SEC-009 | Medium | Image references use mutable tags instead of immutable digests | Kubernetes manifests | Pin tested image digests or enforce signature verification with an admission policy |
| SEC-010 | Medium | Passwordless sudo is granted to the VM administrator account | cloud-init templates | Restrict sudo commands, require stronger operator controls, and use a dedicated automation identity |
| SEC-011 | Medium | Terraform can disable vCenter certificate verification and state contains sensitive values | Terraform | Require a trusted vCenter certificate and move state to an encrypted, access-controlled remote backend |
| SEC-012 | Medium | Argo CD project permits every namespaced resource kind in `dockerelk` | Argo CD project | Replace the wildcard with the exact ECK and core resource kinds required by the application |
| SEC-013 | Medium | Dependabot security updates and code scanning are disabled or absent | GitHub repository | Enable dependency graph, Dependabot alerts and updates, and a CodeQL or equivalent workflow |
| SEC-014 | Medium | Pod Security Admission labels are not applied to `dockerelk` | Kubernetes namespace | Enforce the Kubernetes `restricted` profile after validating ECK compatibility |
| SEC-015 | Low | The lab uses one Elasticsearch node and local-path storage | Kubernetes storage | Add snapshots and restore tests; use replicated storage and multiple nodes for production |

## Vulnerability scan results

Trivy scanned the official Elastic 9.4.2 images on 2026-06-24.

| Image | High detections | Critical detections | Unique CVE/advisory IDs | Detections with a reported fix |
| --- | ---: | ---: | ---: | ---: |
| Elasticsearch 9.4.2 | 43 | 0 | 12 | 43 |
| Kibana 9.4.2 | 39 | 1 | 37 | 38 |
| Logstash 9.4.2 | 34 | 0 | 17 | 34 |

The critical Kibana detection was `CVE-2026-45618` in `liquidjs 10.25.6`;
Trivy reports `10.26.0` as the fixed version.

The most frequent high-severity detections affected:

- Red Hat base packages such as `gnutls`, `openssl`, `libcap`, and `expat`;
- Java libraries including Jackson and Netty;
- Node.js packages including `axios`, `undici`, `ws`, and OpenTelemetry
  packages.

Counts are package detections, not confirmed exploitable attack paths. The same
CVE can appear more than once when a dependency is bundled in multiple
locations. Validate each result against Elastic security advisories, vendor VEX
documents, runtime reachability, and the next available Elastic maintenance
release.

## Configuration scan results

Trivy found six high-severity Dockerfile findings:

- containers run as root;
- `apt-get update` is executed as a separate layer;
- packages are installed without `--no-install-recommends`.

It also reported missing health checks in the Elasticsearch and Kibana legacy
Dockerfiles.

The lowercase `Logstash/dockerfile` was not automatically recognized by Trivy,
which is a scanner coverage gap. Manual review shows the same Ubuntu 16.04,
root-user, and package-installation patterns.

The Trivy Kubernetes CRD scan returned no findings for the `dockerelk`
namespace. This does not override the manual findings: ECK custom resources are
mutated into Pods by the operator, and not every generated setting is evaluated
by static CRD checks.

## Detailed risk notes

### Legacy Docker stack

The legacy path uses Ubuntu 16.04, which ended standard maintenance in April
2021 and requires extended or legacy coverage for later security fixes.
Elastic 6.x is older than the currently supported release families. The
configuration binds Elasticsearch and Kibana to all interfaces and uses
plaintext HTTP without authentication.

Treat this path as migration evidence only:

- keep it stopped by default;
- bind published ports to loopback when temporary execution is unavoidable;
- place it on an isolated network;
- never ingest production credentials or data;
- remove it after migration validation.

### Kubernetes network exposure

Kibana `30601/TCP` and Logstash `30514/TCP` are reachable through each node
address unless an external firewall blocks them. Logstash accepts plaintext
JSON without client authentication.

Preferred design:

- use local port-forward for administration;
- expose Kibana through a trusted ingress with a valid certificate and access
  restrictions;
- protect Logstash with TLS and client authentication;
- add namespace default-deny NetworkPolicies;
- allow Elasticsearch only from Kibana, Logstash, and ECK-required traffic.

### Identity and secrets

ECK-generated credentials are stored as Kubernetes Secrets and retrieved by
local scripts when needed. Kubernetes Secrets are base64-encoded, not encrypted
by default.

For production:

- enable encryption at rest for Kubernetes secrets;
- integrate an external secret manager;
- rotate the `elastic` and Argo CD administrator credentials;
- avoid routine use of the `elastic` superuser;
- issue application-specific roles and service accounts;
- protect kubeconfig and Terraform state with filesystem ACLs and encryption.

### Workload hardening

Effective pod inspection showed:

- Elasticsearch: restricted-style security context;
- Kibana: capabilities dropped, no privilege escalation, read-only root
  filesystem;
- Logstash: no explicit equivalent restrictions.

Add and test the following for Logstash:

```yaml
securityContext:
  runAsNonRoot: true
  seccompProfile:
    type: RuntimeDefault
containers:
  - name: logstash
    securityContext:
      allowPrivilegeEscalation: false
      readOnlyRootFilesystem: true
      capabilities:
        drop:
          - ALL
```

Writable volumes may be required for Logstash data, queues, or temporary files.

## Remediation roadmap

### Immediate

1. Restrict or remove Kibana and Logstash NodePorts.
2. Add default-deny NetworkPolicies.
3. Review and upgrade Elastic images for the reported critical and high CVEs.
4. Retire or hard-isolate the legacy Docker stack.
5. Rotate administrator credentials that have been displayed during
   interactive deployment sessions.

### Short term

1. Add a restricted Logstash security context.
2. Create least-privilege Kubernetes identities for deployment and read-only
   operations.
3. Enable Dependabot and CodeQL or equivalent scanning in GitHub Actions.
4. Add Trivy and Gitleaks checks to pull requests.
5. Pin images and downloaded installers by digest and verify signatures.

### Before production

1. Apply the K3s CIS hardening guide and document exceptions.
2. Enforce Pod Security Admission and admission policies.
3. Use trusted PKI for vCenter, ingress, and operator access.
4. Move Terraform state to an encrypted remote backend.
5. Deploy replicated storage, Elasticsearch redundancy, snapshots, and tested
   disaster recovery.
6. Centralize audit logs and define alerting for authentication and privilege
   events.

## Verification commands

```powershell
gitleaks git --redact .
trivy config .
trivy image docker.elastic.co/elasticsearch/elasticsearch:9.4.2
trivy image docker.elastic.co/kibana/kibana:9.4.2
trivy image docker.elastic.co/logstash/logstash:9.4.2
kubectl auth can-i --list
kubectl get networkpolicy -A
kubectl get services -A
```

## References

- [Elastic product end-of-life policy](https://www.elastic.co/support/eol)
- [Ubuntu release cycle](https://ubuntu.com/about/release-cycle)
- [Kubernetes Pod Security Standards](https://kubernetes.io/docs/concepts/security/pod-security-standards/)
- [K3s CIS hardening guide](https://docs.k3s.io/security/hardening-guide)
- [ECK security documentation](https://www.elastic.co/docs/deploy-manage/security/eck-security)
