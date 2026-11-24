# Cost Optimization Analysis

## Techniques applied
| # | Technique | Before | After |
|---|---|---|---|
| 1 | Image size reduction | `python:3.12` (Debian), single stage, root, dev server | `python:3.12-alpine`, multi-stage, non-root, gunicorn, `.dockerignore`, `--no-cache-dir` |
| 2 | Right-sizing requests/limits | web 250m CPU / 256Mi, Redis 250m / 256Mi | web 100m / 64Mi, Redis 50m / 32Mi (limits tightened to match) |
| 3 | Autoscaling instead of static over-provisioning | fixed 6 web replicas | HPA 2-6 replicas at 50% CPU |
| 4 | Lean Redis | `redis:7`, unbounded memory | `redis:7-alpine`, `maxmemory 48mb` with LRU eviction |

## Measured before/after
Generate this table from your own cluster, then paste it here:

```bash
./scripts/cost-measure.sh before
./scripts/cost-measure.sh after
./scripts/cost-measure.sh report     # also saved to results/cost-table.md
```

(paste output here)

## Cost model
Monthly cost = reserved vCPU x 730 h x $0.0316 + reserved GiB x 730 h x $0.0042 + image GB x $0.10.
Rates are illustrative on-demand figures (editable at the top of `scripts/cost-measure.sh`);
replace them with your provider's price sheet if you want exact numbers. Costs are based on
resources **requested** (reserved), since that is what cloud nodes are sized and billed on.
