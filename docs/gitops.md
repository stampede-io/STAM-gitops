# GitOps workflow

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
