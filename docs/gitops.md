# GitOps workflow

## Blue-green on the gateway (STAM-64)

The gateway is the one service validated by hand rather than gated on
automated analysis (that's booking's and payment's canary Rollouts,
STAM-63) — it's the front door, and a reviewer wants to hit it directly
with real traffic before an all-or-nothing cutover, not watch a gradual
percentage ramp. Its chart (`STAM-gateway/helm/`) uses
`strategy.blueGreen` with `autoPromotionEnabled: false` instead of canary
steps: a new version always lands on the `gateway-preview` Service and
sits there, fully scaled, until a human acts.

```bash
# after a new image syncs, the Rollout pauses with both versions live
kubectl port-forward svc/gateway-preview 8080:80   # validate the new one
kubectl argo rollouts get rollout gateway           # see blue vs preview

kubectl argo rollouts promote gateway                # instant cutover
# or, if it's wrong:
kubectl argo rollouts undo gateway                   # instant rollback
```

Both `promote` and `undo` just repoint the `gateway` Service's selector
between ReplicaSet hashes — there's no gradual traffic shift to wait out,
which is the whole point of blue-green over canary here.

### Verified live (kind, 2026-10-08)

Ran against a real Argo Rollouts controller (v1.10.0) and the real
`kubectl-argo-rollouts` plugin, using a throwaway Rollout with the
identical `strategy.blueGreen` block (not the gateway's own chart — its
Spring Boot app needs more infra up than this check needed):

- a new revision deployed to `preview` while `active` kept serving the
  old version — curled both Services directly and got different
  responses, confirming AC1/AC2
- the Rollout sat `Paused` the whole time; it never auto-promoted (AC5)
- `kubectl argo rollouts promote` switched the active Service to the new
  version immediately — confirmed via curl before/after (AC3)
- `kubectl argo rollouts undo` switched it back immediately — confirmed
  via curl again (AC4)

### A caution for whenever Ingress lands (STMP-43)

Gateway is the one public-facing service in this platform. Any future
Ingress/LoadBalancer config must route to the `gateway` Service, **never**
`gateway-preview` — a copy-paste of the wrong name would quietly put real
user traffic on unvalidated code with no visible error (preview pods are
otherwise healthy). Also see `ignoreDifferences` on both Applications
below: ArgoCD would otherwise fight a paused blueGreen promotion.

## How a change reaches staging

1. A change lands on `STAM-platform`'s `Dev` branch (the umbrella
   chart, or a values file).
2. ArgoCD polls every 3 minutes by default (`stampede-staging`'s
   `targetRevision: Dev`). No action needed here — the next poll picks
   it up, diffs it against the live `staging` namespace, and applies
   it (`syncPolicy.automated`).
3. If `prune: true` wasn't there, a resource removed from the chart
   would be orphaned, left running. It is, so ArgoCD deletes it too.

## How a change reaches prod

1. A tag (`vX.Y.Z`) gets cut on `STAM-platform`'s `main` — `main` only
   receives release merges from `Dev` (CLAUDE.md §9.6), never direct
   commits.
2. `stampede-prod`'s `targetRevision: main` means ArgoCD now sees a
   diff between what's live and what `main` says should be live. No
   `syncPolicy.automated` block means ArgoCD stops there: the
   Application shows `OutOfSync`, nothing changes.
3. A human operator reviews the diff in the ArgoCD UI (`argocd app
   diff stampede-prod`, or the UI's own diff view) and clicks **Sync**
   — or runs `argocd app sync stampede-prod`. That's the one and only
   mutating step a person performs in the entire path from merge to
   prod traffic.

## What happens if someone `kubectl apply`s directly anyway

- **In staging:** ArgoCD's next reconcile (every ~3 min) notices the
  live state no longer matches git, marks the Application
  `OutOfSync`, and — because `selfHeal: true` — reverts it back to
  what git says, without a human doing anything. This is deliberate:
  staging exists to be disposable and always reflect `Dev`.
- **In prod:** same detection (`OutOfSync` appears), but there's no
  `selfHeal` to act on it — prod's manual-only policy means ArgoCD
  reports the drift and waits. Catching that drift *before* someone
  investigates why prod doesn't match git is AC6's job (an alert on
  `OutOfSync` in prod), explicitly deferred to STMP-54, not built yet.

## Verified live (kind)

- Installed ArgoCD via its Helm chart on a kind cluster.
- Applied `argocd/app-of-apps.yaml` by hand (the one manual step this
  repo's README promises is also the last one) and confirmed it
  discovered both `apps/staging/stampede/application.yaml` and
  `apps/prod/stampede/application.yaml` as real child Applications —
  `stampede-staging` and `stampede-prod` appeared in `argocd` with
  exactly the sync policies each file declares (checked
  `.spec.syncPolicy` directly: staging has
  `automated: {prune: true, selfHeal: true}`, prod has none).
- **Both show `Unknown` sync status right now** — not a bug in these
  files, but an honest, logged reason: `platform/charts/stampede:
  app path does not exist` on `Dev` (staging) and `main` (prod). The
  umbrella chart STAM-51 built lives on an unmerged feature branch
  today; it isn't on either branch yet, let alone published to
  `ghcr.io/stampede-io/charts` the way its subcharts need to be. This
  is the same merge-ordering gap already on record from STAM-57/58 —
  not new, just visible here too.
- Because of that, the `selfHeal` vs. manual-sync *behavior* (AC4/AC5)
  was proven against two throwaway Applications using the exact same
  `syncPolicy` blocks, pointed at a trivial ConfigMap manifest in this
  repo instead of the blocked chart path — isolating the sync-policy
  mechanism from the separate, already-documented chart-publishing
  gap:
  - Automated (staging-equivalent): `kubectl patch`ed the live
    ConfigMap directly, watched the Application flip to `OutOfSync`,
    then watched it revert to the git value on its own within
    seconds — no `argocd app sync` run.
  - Manual (prod-equivalent): same direct patch, confirmed the
    Application correctly reports `OutOfSync` and **stays** drifted —
    the ConfigMap keeps the manually-patched value — until `argocd app
    sync` is run by hand.
