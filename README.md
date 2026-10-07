# STAM-gitops

ArgoCD's source of truth for STAMPEDE (STAM-61 / STMP-49). Git is the
only deploy path once ArgoCD owns a cluster — nobody runs `kubectl
apply` against staging or prod again; they open a PR here instead.

## Layout

```
argocd/app-of-apps.yaml   # the one Application a human applies by hand
apps/staging/stampede/    # auto-synced, self-healing
apps/prod/stampede/       # manual-sync only
docs/gitops.md            # the actual workflow: how a change reaches prod
```

## One Application per environment, not per service

AC1 describes `apps/staging/<service>/` — a directory per service.
What's here instead is one Application per environment, each pointing
at `STAM-platform`'s existing umbrella chart
(`platform/charts/stampede`) with that environment's values file.

That's deliberate, not a shortcut: STAM-51 already built, tested, and
documented a single Helm release that deploys all 6 services together
specifically so `helm install stampede ...` is one command, not six.
Splitting ArgoCD into six independent per-service Applications here
would manage the exact same charts a second, parallel way — fighting
the chart's own design rather than using it. If a service ever needs
independent release cadence from the others (a real reason to split),
that's the trigger to revisit this, not before.

## Bootstrapping a cluster

```bash
helm install argocd oci://ghcr.io/argoproj/argo-helm/argo-cd -n argocd --create-namespace
kubectl apply -f argocd/app-of-apps.yaml
```

That one `kubectl apply` is also the *last* one — from here, `stampede-staging` and `stampede-prod` exist because the app-of-apps Application found them under `apps/`, and every change to either flows through a PR to this repo.

See `docs/gitops.md` for the day-to-day workflow and the real limitation this is tested against: `platform/charts/stampede` doesn't exist on `STAM-platform`'s `Dev` or `main` yet (STAM-51's umbrella chart lives on an unmerged feature branch) — confirmed live via ArgoCD's own error message, `app path does not exist` — so until that merges, `stampede-staging`/`stampede-prod`'s Applications show `Unknown`. ArgoCD itself, the app-of-apps discovery, and the sync-policy behavior (automated+selfHeal for staging, manual for prod) are all verified live independent of that, against throwaway Applications pointed at a trivial manifest instead — see `docs/gitops.md`.
