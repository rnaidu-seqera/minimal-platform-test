# FD-7531 — CE config + pipeline config merge test

Minimal pipeline that demonstrates how Seqera Platform combines the
Compute Environment's "Nextflow config file" with the pipeline's own
`nextflow.config` at launch time.

## What this MRE tests

Customer claim (FD-7531, Eli Lilly): adding a per-process block to the
pipeline's `nextflow.config`, e.g.

```groovy
process { withName: "...." { scratch = true } }
```

"completely overwrites" the CE's `nextflow.config` on launch.

This MRE is set up to falsify that claim. The CE config (in
`ce-nextflow-config.txt`) sets four top-level `process` directives:

| Directive          | CE value     |
|--------------------|--------------|
| `cpus`             | `1`          |
| `scratch`          | `true`       |
| `ext.from_ce`      | `'yes'`      |
| `ext.shared_key`   | `'from-CE'`  |

The pipeline `nextflow.config` only declares a `withName: 'OVERRIDE_ME'`
selector that sets `cpus = 2`, `scratch = false`, and
`ext.shared_key = 'from-pipeline'`. It does **not** redeclare anything
at the top-level `process` scope.

## Expected output

If Platform merges the two configs (and Nextflow's selector semantics
behave as documented), the two processes should print:

**BASE_DEFAULTS** (not matched by the selector — should be 100% CE):
```
task.cpus            = 1
task.ext.from_ce     = yes
task.ext.shared_key  = from-CE
```

**OVERRIDE_ME** (matched by the selector — keys not in the selector
should still come from the CE):
```
task.cpus            = 2            ← overridden by pipeline
task.ext.from_ce     = yes          ← inherited from CE
task.ext.shared_key  = from-pipeline ← overridden by pipeline
```

If the customer's claim were correct, OVERRIDE_ME would instead show
`task.ext.from_ce = null` (CE block wiped out) and BASE_DEFAULTS might
also lose its CE-supplied values.

## How to run it on Seqera Platform

1. **Set the CE config**: open the Compute Environment you'll launch
   from → Edit → paste the contents of `ce-nextflow-config.txt` into
   the **Nextflow config file** field → Save.
2. **Add the pipeline to Launchpad** (or launch ad-hoc) pointing at
   this repository, branch `FD-7531`. Leave the pipeline-level
   "Nextflow config file" field on the Launchpad form **empty** — the
   `nextflow.config` checked into the repo is what we're testing.
3. **Launch the run**.
4. **Inspect the task logs** for both `BASE_DEFAULTS` and `OVERRIDE_ME`
   (Run page → Tasks → click each task → `.command.log` /
   `.command.out`). Compare against the expected output above.

### Optional: also check the resolved config

On the Run page, the "Configuration" tab shows the fully merged config
that Nextflow used. You should see both the CE-level `process` block
and the pipeline's `withName: 'OVERRIDE_ME'` selector present together
— this is the direct visual proof that Platform did not discard the CE
config.

## What this means for the customer

- They do **not** need to copy-paste their entire CE `nextflow.config`
  into each pipeline's `nextflow.config`.
- Per-process tweaks belong inside `withName:` (or `withLabel:`)
  selectors — those are additive and only override the directives they
  explicitly set.
- Where the customer's perception of "complete overwrite" likely comes
  from: declaring the same property at the **top-level** `process`
  scope in the pipeline config will override the CE's top-level value
  for that one property (Nextflow's normal last-wins merge). It does
  not, however, wipe out the rest of the CE block.
