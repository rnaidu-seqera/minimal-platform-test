# MRE — FD-7749 / platform#11971: sign IGV reference genome URLs

Tests `fix(data-explorer): sign IGV reference genome URLs` (label `enterprise/26.1.5`) on **both GCS
and Azure Blob Storage**. The originating customer is on Azure, so Azure is the environment that
actually matters here — GCS is the cheaper smoke test.

## What the PR fixes

`IgvConfigService.resolveConfig$` signed only **track** URLs. A custom reference genome in a private
bucket was handed to igv.js **unsigned**, so the browser's fetch was rejected and the genome never
loaded. Two gaps:

1. **Reference-only configs were skipped outright.** `if (!config.tracks?.length) return of(config)`
   returned early — and a config that registers a custom genome is exactly the shape with a
   `reference` and no `tracks`.
2. **`collectUniqueUrls` walked `tracks` only**, so `reference.*` URLs went unsigned even when tracks
   *were* present.

The fix collects `reference.*` fields (`fastaURL`, `indexURL`, `cytobandURL`, `aliasURL`,
`chromSizesURL`, `twoBitURL`, `compressedIndexURL`) plus genome-level `reference.tracks`, and signs
them in the same resolve/sign batch as track URLs.

**Frontend-only.** No backend or API change, which is why the same fixtures work unchanged across
providers — `/data-links/resolve` and `/data-links/sign-urls` are already generic over URL lists.

## Why this needs JSON config fixtures

This code path is reachable **only** by opening a user-authored IGV JSON config in Data Explorer.
Opening a FASTA file directly makes it a *track* against the hardcoded genome — a different path,
covered by #11324. Registering a custom **reference** only happens via the config path, which #11324
left untouched.

So the fixtures are config files plus a synthetic genome for them to point at.

## Fixtures

The genome is a synthetic 10 kb contig named **`chrTest`**, deliberately not a real genome. If the
reference fails to load, nothing renders at all — that's the signal.

| Config | Shape | Isolates |
| --- | --- | --- |
| `genome-only.json` | `reference`, no `tracks` | gap 1 — the early return |
| `genome-with-track.json` | `reference` + session `tracks` | gap 2 — reference collected even with tracks |
| `genome-nested-tracks.json` | `reference.tracks` | genome-level tracks also signed |
| `genome-chromsizes.json` | `reference.chromSizesURL` | a field the bundled igv typings omit |

Supporting objects: `reference.fasta`, `reference.fasta.fai`, `chrTest.chrom.sizes`, `sample.bam`,
`sample.bam.bai`, `features.bed` — the BAM and BED are aligned to `chrTest`, so they only render if
the custom reference loaded.

## A trap worth knowing before you start

Per the PR's own context: **a config that fails to parse degrades silently to the text/JSON viewer.**
The IGV view mode is simply never offered, with no error shown. The originating customer lost weeks to
this — their genome JSON had an unquoted key and a trailing comma.

So if a config opens as plain text with no IGV option, that is *not* this bug. It means the JSON was
rejected. The pipeline validates every config with `json.load` before publishing, so a green run rules
this out — but keep it in mind if you hand-edit any config.

---

# Part 1 — GCS

## Step 1: launch

Revision `test/FD-7749-igv-reference-signing`, GCP Batch CE, and **`outdir` set to an absolute
`gs://` path** — e.g. `gs://rashmi-project-sandbox-batch-work/pr3-mre`.

`outdir` is baked into the config files as the reference genome's URLs, so a relative path yields
configs that point nowhere. Wait for all three tasks green.

## Step 2: open the reference-only config

Data Explorer → `pr3-mre/` → click **`genome-only.json`**.

Platform should offer an **IGV** view mode alongside the raw JSON. Switch to it.

- ✅ **Fixed:** the genome loads. Chromosome selector shows `chrTest`, the sequence track renders when
  you zoom in, and Network shows signed requests for `reference.fasta` and `reference.fasta.fai`.
- ❌ **Unpatched:** the viewer is empty or errors, and Network shows the FASTA requested at its raw
  `gs://`-derived URL with **no signature** — or no request at all.

This is the primary case. Pre-patch it failed outright because reference-only configs never reached
the signing code.

## Step 3: reference plus session tracks

Open **`genome-with-track.json`** → IGV view. Navigate to `chrTest:1,000-1,600`.

Both the reference *and* the BAM track must be signed. Pre-patch the tracks were signed but the
reference wasn't, so this is the case that "half-worked" — check both:

- `reference.fasta` / `.fai` → signed, 200
- `sample.bam` → 206 range reads, `sample.bam.bai` → 200
- 100 reads render as a pileup

## Step 4: genome-level tracks

Open **`genome-nested-tracks.json`** → IGV view → `chrTest:3,000-3,600`.

The BED track is nested *inside* `reference.tracks`, which igv.js concatenates with session tracks.
Expect a signed request for `features.bed` and 10 features rendering.

## Step 5: chromSizesURL

Open **`genome-chromsizes.json`** → IGV view. Expect a signed request for `chrTest.chrom.sizes`
alongside the FASTA pair.

## How to confirm signing

For each case, the check is the same: in Network, the requests for reference files must carry a
signature — `X-Goog-Signature` on GCS, a SAS query string (`sig=`, `se=`, `sp=`) on Azure — and return
**200**. An unsigned request to a private bucket returns **401/403**, and a *missing* request means the
config never reached the signing code at all.

---

# Part 2 — Azure Blob Storage

The customer environment. The container **must be private** — a public container would load with or
without the fix and prove nothing. Azure's default for new containers is "No public access", which is
what we want.

No Azure Batch compute environment is needed: the fixtures are static, so they're copied over rather
than regenerated.

## Step A: install the CLI (no Homebrew)

```
conda create -y -n azcli -c conda-forge python=3.12 azure-cli
conda activate azcli
az --version
az login
```

Python 3.12 rather than your base 3.13, which recent `azure-cli` releases don't fully support.

## Step B: create the storage account and private container

```
RG=seqera-igv-test
ACCT=seqeraigvtest$RANDOM        # must be globally unique, lowercase alphanumeric, 3-24 chars
LOC=eastus

az group create --name $RG --location $LOC
az storage account create --name $ACCT --resource-group $RG --location $LOC --sku Standard_LRS
KEY=$(az storage account keys list --account-name $ACCT --resource-group $RG --query '[0].value' -o tsv)
az storage container create --name igv-test --account-name $ACCT --account-key "$KEY"
```

`az storage container create` defaults to private access. Record `$ACCT` and `$KEY` — both go into the
Platform credential.

## Step C: CORS on the Blob service

Configured per **storage account**, not per container:

```
az storage cors add --services b --methods GET HEAD \
  --origins https://enterprise.stage-tower.net \
  --allowed-headers '*' --exposed-headers '*' --max-age 3600 \
  --account-name $ACCT --account-key "$KEY"
```

`Range` must be permitted for IGV's indexed reads — `'*'` covers it. Same requirement as GCS, set in a
different place.

## Step D: copy the fixtures from GCS

Azure can copy server-side from any HTTP source, so generate short-lived signed GCS URLs and let Azure
pull them. No local download, no `azcopy`.

```
GCS=gs://rashmi-project-sandbox-batch-work/pr3-mre
for f in reference.fasta reference.fasta.fai chrTest.chrom.sizes sample.bam sample.bam.bai features.bed; do
  URL=$(gcloud storage sign-url "$GCS/$f" --duration=1h --format='value(signed_url)')
  az storage blob copy start --destination-container igv-test --destination-blob "$f" \
    --source-uri "$URL" --account-name $ACCT --account-key "$KEY"
done
```

`gcloud storage sign-url` needs a service-account key; if your user credentials can't sign, use
`--impersonate-service-account` or download and upload with
`az storage blob upload-batch --destination igv-test --source <local-dir>` instead.

## Step E: rewrite the configs for Azure

The configs must reference `az://` paths, so they can't be copied — regenerate them:

```
sed 's#gs://rashmi-project-sandbox-batch-work/pr3-mre#az://igv-test#g' \
  genome-only.json > genome-only.azure.json
```

...for each of the four, then upload. Or re-run the pipeline with
`outdir = az://igv-test/...` if you'd rather have Nextflow generate them — but that needs Azure
credentials in the run, which the copy approach avoids.

## Step F: Platform setup

1. **Credentials** → Add → **Azure** → storage account name `$ACCT` and access key `$KEY`.
2. **Data Explorer** → Add data repository → **Azure** → `az://igv-test` → those credentials.
3. Click into it and confirm the six objects list. Same gate as GCS: a link that exists but can't list
   will fail at preview time and mimic the bug.

## Step G: repeat Steps 2–5

Identical procedure, with one difference in what you're looking for: Azure signs with a **SAS token**,
not a V4 query signature. So the reference requests should hit
`https://$ACCT.blob.core.windows.net/igv-test/reference.fasta?...sig=…` with a `sig=` parameter and
return **200**.

Unsigned means **401/403** from Azure. A missing request means the config never reached the signing
code.

## Why testing both matters

The PR is provider-agnostic — signing goes through the same generic endpoints. But Azure exercises a
different `DataLinkClient` implementation and a different signing mechanism (SAS vs V4 query params),
and the customer is on Azure. Passing on GCS does not establish that Azure works.
