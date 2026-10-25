# AGENTS.md

GitOps homelab: a k3s cluster reconciled by ArgoCD from this repo. There is no
application code, test suite, or CI here — Kubernetes/Helm YAML, plus the
Dockerfiles in `dockerfiles/` for the custom images.

**Deploying = committing and pushing to `master`.** ArgoCD auto-syncs every
Application from `git@github.com:AgostaGiorgio/HomeLab.git` (`master`) with
`prune` + `selfHeal`, so a merged/pushed change hits the live cluster.

## Layout

- `infra/infra-app.yaml`, `apps/apps-application.yaml`, `shared/shared-application.yaml`
  are the three root app-of-apps. Each auto-discovers `<group>/*/application.yaml`.
  A new app is picked up just by adding that file.
- `charts/` holds local reusable Helm charts (`applications` = generic
  `base-application`, plus `postgresql`, `ollama`, `qbittorrent`, `s3`). Charts
  here are not deployed directly.
- `dockerfiles/` holds Dockerfiles for the custom images published to
  `registry.agogi.dev` (`custom-n8n-runners`, `opencode-cli`). `custom-n8n` has
  no Dockerfile here (it is upstream `n8nio/n8n` re-tagged). Not deployed by
  ArgoCD; build/push manually (see `dockerfiles/README.md`).
- `test/` is local scratch/recovery material and is **gitignored** — nothing in it
  ever deploys.
- Destination namespace is set per Application and often differs from the folder
  name: `postgresql` → `postgres`, `registry` → `registry`, `sealed-secrets` →
  `kube-system`.

## App patterns

- Most app dirs are umbrella charts: a `Chart.yaml` + `values.yaml`, with
  dependencies resolved by `file://../../charts/<chart>` (local) or upstream
  Helm repo URLs. Raw manifests live in `<app>/config/*.yaml` and are delivered
  as a second ArgoCD source.
- `apps/media-server` is the exception: its Application points Helm at
  `apps/media-server/chart` and manifests at `apps/media-server/config`.
- External upstream charts (`traefik`, `sealed-secrets`, `authentik`,
  `docker-registry`) use the multi-source `ref: values` pattern, so their values
  are `$values/<dir>/values.yaml`.

## Local verification (no cluster needed)

Local `file://` chart dependencies are **not** vendored or committed, so plain
`helm template` fails with "missing in charts/ directory". Build first:

```bash
helm dependency build apps/mtrack && helm template mtrack apps/mtrack
helm lint apps/mtrack
```

`helm dependency build` writes `charts/*.tgz` and `Chart.lock` into the app dir;
they are untracked — do not commit them. `kubectl apply --dry-run=client -f <file>`
needs a kubeconfig. The `kubeseal` and `argocd` CLIs are not installed locally.

## Conventions and gotchas

- Branch is `master` (not `main`). Most Applications pin `targetRevision: master`;
  `authentik`/`registry` use `HEAD`.
- Domain is `agogi.dev`. TLS is Traefik (`ingressClassName: traefik`) plus
  cert-manager Cloudflare DNS01 via `cloudflare-production-cluster-issuer`.
  App images are pulled from `registry.agogi.dev`.
- Secrets are `SealedSecret` CRs (`bitnami.com/v1alpha1`), namespace-scoped. They
  can only be decrypted by the cluster's sealed-secrets signing key. If
  sealed-secrets is ever rebuilt, restore the old keys **first** (see
  `test/sealed/`), otherwise re-seal everything. Sealing is done with `kubeseal`
  on the server.
- Media/Postgres PVCs bind node-local hostPath PVs (e.g.
  `/mnt/ssd1/media-server`) with `storageClassName: ""`; they are not portable
  between nodes.
- `shared/postgresql/Chart.yaml` still declares `name: ollama` (copy-paste bug).
  Harmless because ArgoCD deploys by path, not chart name — leave it unless
  intentionally fixing.

## References

- `README.md` — full server/k3s/ArgoCD/Tailscale bootstrap and troubleshooting.
- `test/old_doc/` — older step-by-step guides (some IPs are stale). Trust the
  manifests/config over the prose.
