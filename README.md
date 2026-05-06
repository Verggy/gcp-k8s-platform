# gcp-gke-gitops-stack

Infrastructure-as-code project that provisions a GKE cluster with production-style patterns on GCP and bootstraps a full cloud-native stack on top of it: ingress, TLS, secret sync, GitOps, observability, and a sample workload. Designed for quick setup and portability.

Two environments (`dev` and `prod`) are provisioned from the same Terraform modules and reconciled into the same shape by ArgoCD; per-environment differences (project ID, hostnames, autoscaling caps) live in a single values file each.

![alt text](https://github.com/Verggy/gcp-gke-gitops-stack/blob/main/docs/images/architecture.drawio.png "Diagram")

## Architecture

The system has three layers:

1. **Terraform** provisions the GCP-side: VPC, subnets, Cloud NAT, GKE cluster with two node pools, GCP Secret Manager entries (Cloudflare token, Grafana credentials, ArgoCD credentials), GCS bucket for Loki chunks, Cloudflare DNS records and the Workload-Identity-bound service accounts the in-cluster components impersonate.
2. **Helmfile** bootstraps the cluster in a strict dependency order: `external-secrets-operator` → `cert-manager` → `prometheus-crds` → `external-secrets-config` → `ingress-nginx` → `argocd-secrets` → `argocd` → `argocd-bootstrap`. After the last release, ArgoCD owns everything else.
3. **ArgoCD** runs an `app-of-apps` against `argocd/applications/`. Every file in that directory is an `ApplicationSet` keyed off cluster labels — adding a file there is how new components are onboarded.

### Network and node pools

- Regional GKE in `europe-central2` with private nodes, public control-plane endpoint, regular release channel, Workload Identity pool `<project>.svc.id.goog`.
- VPC with primary subnet plus secondary ranges for pods and services. Cloud Router + Cloud NAT provides egress for private nodes.
- One static external IP per env, attached to the `ingress-nginx` service. Cloudflare A records point at it.
- **`web-node-pool`**: spot vms, no taint — runs `webapp` (Online Boutique).
- **`infra-node-pool`**: on-demand, taint `purpose=infra:NoSchedule` — runs `ingress-nginx`, `cert-manager`, `external-secrets-operator`, `argocd`, and `monitoring` namespace. Promtail and node-exporter (DaemonSet, tolerates everything) runs on both pools.

### TLS, secrets, and GitOps flow

- **TLS** — `cert-manager` uses ACME DNS-01 via Cloudflare. Every ingress gets a cert automatically.
- **Secrets** — Terraform writes secrets into GCP Secret Manager. `external-secrets-operator` (KSA → GSA via Workload Identity) pulls them every hour through a `ClusterSecretStore`. Per-namespace `ExternalSecret` resources materialise them as native K8s `Secret`. No static service-account keys anywhere.
- **GitOps** — Helmfile installs ArgoCD itself, then a single root `Application` (`bootstrap`) syncs from `argocd/applications/`. Each `ApplicationSet` there uses a `clusters` generator that selects clusters by the label `argocd.argoproj.io/secret-type=cluster` and templates per-env values out of the in-cluster Secret's labels (`grafana_host`, `shop_host`, `project_id`, `env`) and annotation (`repo_url`). One repo, multiple environments, no branching.

## Repository layout

```
.
├── argocd/applications/              # ApplicationSets — one per deployable unit
├── environment-values/{dev,prod}.yaml  # per-env hostnames, project IDs, ingress IP
├── helm/                             # local charts + values for each release
│   ├── argocd/{bootstrap,secrets}/   # root-app chart + ArgoCD ExternalSecret + in-cluster Secret
│   ├── cert-manager/                 # values + ClusterIssuer + ExternalSecret
│   ├── external-secrets-operator/    # values + ClusterSecretStore
│   ├── grafana/                      # values + grafana-admin ExternalSecret
│   ├── ingress-nginx/                # values
│   ├── loki/                         # values
│   ├── online-boutique/              # values + ingress chart
│   ├── prometheus/                   # values + PrometheusRules
│   └── promtail/                     # values
├── helmfile.yaml                     # bootstrap orchestration with needs: ordering
├── terraform/
│   ├── environments/
│   │   ├── foundation/               # WIF pool, terraform SAs, IAM grants — bootstrap only
│   │   ├── dev/                      # dev project IaC
│   │   └── prod/                     # prod project IaC
│   └── modules/
│       ├── vpc/                      # VPC + subnet + Cloud Router + Cloud NAT
│       ├── gke/                      # cluster + 2 node pools
│       ├── dns/                      # static IP + Cloudflare A records
│       ├── external-secrets/         # Secret Manager secrets + ESO GSA + WI binding
│       └── loki/                     # GCS bucket + loki GSA + WI binding
├── scripts/
│   └── bootstrap.sh                  # (one-time use) GCP project + state bucket + TF SA setup
└── .github/workflows/
    ├── terraform-dev.yaml            # dev plan on PR, apply on push to main
    └── terraform-prod.yaml           # prod plan on PR, apply on push to main
```

## Prerequisites

- A GCP **organization** and **billing account** you can attach projects to.
- A **Cloudflare** account with a delegated zone (the apex domain you want to use), plus an API token with `Zone:DNS:Edit` on that zone.
- Local tools: `gcloud`, `terraform`, `helmfile`, `helm`, `kubectl`, `openssl`.
- Repository forked or cloned to a GitHub repo you control (the WIF binding constrains tokens to one specific `owner/repo`).

## Bootstrap (one-time, all envs)

`scripts/bootstrap.sh` creates the three GCP projects (`infra-tf-state-XXXX`, `infra-dev-XXXX`, `infra-prod-XXXX`), provisions the GCS state bucket, and creates the `terraform@<env>.iam.gserviceaccount.com` service accounts with the IAM roles Terraform needs.

```bash
gcloud auth login
gcloud auth application-default login

./scripts/bootstrap.sh \
  --org-id          <ORG_ID> \
  --billing-account <BILLING_ACCOUNT_ID>
```

It prints the state bucket name and the dev/prod project IDs at the end — keep them. Then:

1. Point ADC at the state project for quota/billing, otherwise the GCS backend fails with a `403 SERVICE_DISABLED` on `terraform init`:
```bash
gcloud auth application-default set-quota-project <state-project-id>
```
2. Update `terraform/environments/{dev,prod}/backend.tf` and `terraform/environments/foundation/backend.tf` to point at the new state bucket.
3. Update `terraform/environments/{dev,prod}/terraform.tfvars` with the new project IDs.
4. Update `terraform/environments/foundation/terraform.tfvars` with the new project IDs and `github_repository = "<owner>/<repo-name>"`.
5. Apply the foundation stack — this wires Workload Identity Federation between your GitHub repo and the two terraform SAs:
   ```bash
   cd terraform/environments/foundation
   terraform init && terraform apply
   ```
6. Add these GitHub Actions secrets so the workflows can authenticate via OIDC (WIF_* values are exposed as Terraform outputs by the foundation stack):

   | Secret                       | Value                                                                  |
   | ---------------------------- | ---------------------------------------------------------------------- |
   | `WIF_PROVIDER_DEV`           | `projects/<dev-project-number>/locations/global/workloadIdentityPools/github-pool/providers/github-provider` |
   | `WIF_SERVICE_ACCOUNT_DEV`    | `terraform@<dev-project-id>.iam.gserviceaccount.com`                   |
   | `WIF_PROVIDER_PROD`          | (same, with prod project number)                                       |
   | `WIF_SERVICE_ACCOUNT_PROD`   | `terraform@<prod-project-id>.iam.gserviceaccount.com`                  |
   | `cloudflare_token`           | Cloudflare API token with `Zone:DNS:Edit` on your zone                 |
   | `cloudflare_zone_id`         | The Cloudflare zone ID for your domain                                 |

## Provisioning an environment

For each env (`dev` and `prod`):

```bash
cd terraform/environments/dev    # and prod

# secrets.tfvars is gitignored — create it locally for local terraform plan/apply:
cat > secrets.tfvars <<EOF
cloudflare_token   = "<cloudflare-api-token>"
cloudflare_zone_id = "<cloudflare-zone-id>"
EOF

terraform init
terraform plan  -var-file="secrets.tfvars"
terraform apply -var-file="secrets.tfvars"
```

After `apply` finishes, `terraform output ingress_ip` prints the static IP.\
In `environment-values/{dev,prod}.yaml` — replace `*.<domain>` host values with your domain, `<owner>/<repo-name>` with your values and `ingress_ip: "x.x.x.x"` with your ingress ip. Dev hosts are prefixed with `dev-` so dev and prod can share a zone safely.

## Cluster bootstrap (Helmfile)

```bash
gcloud container clusters get-credentials <env>-cluster --region europe-central2

helmfile -e dev sync      # apply in dependency order
```

The releases are sequenced via `needs:` in `helmfile.yaml`:

```
external-secrets → cert-manager → prometheus-crds → external-secrets-config (CSS + ClusterIssuer) → cert-manager-secrets 
→ ingress-nginx → argocd-secrets → argocd → argocd-bootstrap (root Application)
```

Once `argocd-bootstrap` is synced, ArgoCD pulls in the rest (`prometheus`, `grafana`, `loki`, `promtail`, `online-boutique`, …) by reading `argocd/applications/`. Watch progress with:

```bash
kubectl -n argocd get applications
```

The first sync takes a few minutes — Prometheus CRDs install, cert-manager issues certs, Loki creates its GCS layout, Online Boutique pulls 11 images.

## GitHub Actions

Two workflows (`terraform-dev.yaml`, `terraform-prod.yaml`) trigger on changes under `terraform/environments/<env>/**` or `terraform/modules/**`:

- **Pull request** — `terraform plan` only.
- **Push to `main`** — `terraform apply -auto-approve`.
- **Manual `workflow_dispatch`** — runs `plan`.

Authentication is OIDC → WIF → terraform SA, no static keys.

To skip CI on a particular commit (useful for non-functional refactors), include `[skip ci]` in the **head commit message** — applies to both `push` and `pull_request` runs. With squash-merges, set the marker in the squashed commit message.

## Customising for your domain

If your zone isn't on Cloudflare you'd also need to swap the cert-manager DNS-01 solver (`helm/cert-manager/cluster-issuer.yaml`) and the `cloudflare_record` resources in `terraform/modules/dns/main.tf`.

## What gets deployed

| Layer        | Component             | Namespace                    | Notes                                            |
| ------------ | --------------------- | ---------------------------- | ------------------------------------------------ |
| Ingress      | ingress-nginx 4.15.1  | `ingress-nginx`              | LoadBalancer Service bound to static IP          |
| TLS          | cert-manager v1.20.2  | `cert-manager`               | Let's Encrypt + Cloudflare DNS-01                |
| Secrets      | external-secrets 2.3.0| `external-secrets-operator`  | ClusterSecretStore → GCP Secret Manager via WI   |
| GitOps       | ArgoCD 9.5.4          | `argocd`                     | App-of-apps from `argocd/applications/`          |
| Metrics      | kube-prometheus-stack 83.7.0 | `monitoring`         | Prometheus + Operator + node-exporter + KSM      |
| Dashboards   | Grafana 10.5.15       | `monitoring`                 | Datasources: Prometheus + Loki                   |
| Logs         | Loki 6.55.0           | `monitoring`                 | Chunks/ruler/admin → GCS via Workload Identity   |
| Log shipping | Promtail 6.17.1       | `monitoring`                 | DaemonSet — runs on every node                   |
| Application  | Online Boutique 0.10.5| `webapp`                     | OCI chart, ~11 microservices, web-node-pool      |

Three hostnames are exposed via ingress-nginx: `argocd.<domain>`, `grafana.<domain>`, `shop.<domain>` (prefixed with `dev-` in dev).

## Day-to-day operations

```bash
# Switch kubeconfig context
gcloud container clusters get-credentials <env>-cluster --region europe-central2

# Get nodes with zones they're in
kubectl get nodes -o custom-columns="NAME:.metadata.name,ZONE:.metadata.labels['topology\.kubernetes\.io/zone'],STATUS:.status.conditions[-1].type"

# Get pods with zones they're in
kubectl get pods -A --field-selector='metadata.namespace!=kube-system' -o json |\
jq -r '.items[] | [.metadata.namespace, .metadata.name, .spec.nodeName] | @tsv' |\
while IFS=$'\t' read ns pod node;\
  do
  zone=$(kubectl get node "$node" -o jsonpath='{.metadata.labels.topology\.kubernetes\.io/zone}'); \
  printf '%s\t%s\t%s\t%s\n' "$ns" "$pod" "$zone";\
done

# Get argocd password
gcloud secrets versions access latest --secret=argocd-admin --project <project_id> | jq -r '.password'

# Get the Grafana admin password
kubectl get secret grafana-admin -n monitoring -o jsonpath='{.data.admin-password}' | base64 -d ; echo

# Set online-boutique loadgenerator to generate more load:
kubectl set env deployment/loadgenerator -n webapp USERS=500 RATE=20
```

To add a new component: drop a new `ApplicationSet` into `argocd/applications/`, add the chart values under `helm/<name>/`, push. ArgoCD picks it up on the next refresh.

## Cleanup

```bash
# In each env (dev, prod) — order matters: tear down workloads, then infra
helmfile -e <env> destroy
cd terraform/environments/<env> && terraform destroy -var-file="secrets.tfvars"

# Foundation stack — only if you're decommissioning the GitHub integration
cd terraform/environments/foundation && terraform destroy

# Finally, delete the GCP projects (gcloud projects delete <id>) and the state bucket.
```

`google_container_cluster.deletion_protection = false` is set deliberately so `terraform destroy` succeeds without manual intervention as this is portfolio project. **Do not flip that on prod-grade clusters.**

## Sensitive files

The `.gitignore` blocks `**.tfvars` by default and whitelists only the non-sensitive `terraform.tfvars` files. Never commit:

- `terraform/environments/*/secrets.tfvars`
- `*.tfstate*`
- `**/.terraform*`

Verify with `git status` before committing in `terraform/`.

## TODO
- [ ] Deploy Velero
- [ ] HA for observability
- [ ] Deploy OTel Collector
- [ ] Deploy Tempo

## License

MIT — see `LICENSE`.
