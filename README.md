# MRE — PLAT-5733 / platform#11624: GCS V4 signing for genomic files

Tests `fix: sign GCS genomic file URLs with V4 for IGV preview` (label `enterprise/26.1.5`) on a
Seqera Platform Enterprise instance with a GCP Batch compute environment. Follow-up to #11324.

## What the PR changes

A **backend** change, confined to `GoogleDataLinkClient.groovy`. No frontend change.

igv.js decides whether a URL is signed by checking for `X-Goog-Signature` — a **V4** parameter.
Platform previously signed all GCS URLs with **V2** (`GoogleAccessId`/`Expires`/`Signature`), so
igv.js concluded the link was unsigned and rewrote it to the GCS **JSON API** endpoint
(`storage.googleapis.com/storage/v1/b/<bucket>/o/<object>?…&alt=media`). That endpoint ignores
query-string signatures and expects an OAuth bearer token, so the request was rejected as an
anonymous caller — **401**, `Anonymous caller does not have storage.objects.get access`.

The fix signs *genomic* files with V4. The URL then carries `X-Goog-Signature`, igv.js recognises it,
skips the rewrite, and the request stays on the XML API where query-string signatures are honoured.

## The part worth testing hardest

V4 signs the entire query string, and the pinned `google-cloud-storage:1.102.0` can't include the
`response-content-*` params in a V4 signature. So the genomic branch does an early `return url`,
**dropping `response-content-disposition` and `response-content-type` entirely**. Non-genomic files
keep V2 with both params appended as before.

`GENOMIC_FILE_SUFFIXES` includes plain-text formats — `.bed`, `.vcf`, `.gtf`, `.gff`, `.gff3`,
`.wig`, `.bedgraph`, `.fasta`, `.fa`. Those used to download with `attachment; filename=…` and now
carry no `Content-Disposition` at all. **Whether clicking Download still downloads them, rather than
rendering them in a browser tab, is the untested consequence of this change** — and it isn't in the
PR's own test plan.

Binary genomic files (`.bam`, `.cram`, `.bam.bai`) are unaffected in practice: browsers download
`application/octet-stream` regardless of disposition.

## Fixtures

| File | Classified | Signature expected | Why it's here |
| --- | --- | --- | --- |
| `sample.bam` + `.bai` | genomic | **V4** | the original bug: index fetch on locus search |
| `variants.vcf.gz` + `.tbi` | genomic | **V4** | second indexed format |
| `variants.vcf` | genomic | **V4** | plain text on the V4 path → download check |
| `features.bed` | genomic | **V4** | plain text on the V4 path → download check |
| `annotations.gtf` | genomic | **V4** | plain text on the V4 path → download check |
| `reference.fasta` | genomic | **V4** | plain text on the V4 path → download check |
| `report.txt` | not genomic | **V2** | control: V2 path must be unchanged |
| `data.csv` | not genomic | **V2** | control: inline preview via response-content-type |
| `report.html` | not genomic | **V2** | control: inline rendering |

## Prerequisites

Same as #11324, and both are hard requirements:

1. **A Data Link covering the bucket**, and `storage.buckets.get` on it —
   `roles/storage.objectAdmin` alone is not enough (use `roles/storage.legacyBucketReader` on the
   bucket, or `roles/storage.bucketViewer` at project level for auto-discovery too).
2. **A bucket CORS policy** allowing the Platform origin for `GET`/`HEAD` with `Range` exposed. This
   PR makes CORS *newly load-bearing*: V2 previously masked its absence by routing through the
   CORS-permissive JSON API. `gcs-cors.json` in this repo is a working starting point.

## How to read the signature version

Don't guess from the truncated Network row. Click the file in Data Explorer, find the
**`generate-download-url`** request, and read the `url` field in its **JSON response**:

| Version | Query parameters present |
| --- | --- |
| **V4** | `X-Goog-Algorithm=GOOG4-RSA-SHA256`, `X-Goog-Credential`, `X-Goog-Date`, `X-Goog-Expires`, `X-Goog-SignedHeaders`, `X-Goog-Signature` |
| **V2** | `GoogleAccessId`, `Expires`, `Signature` |

The response body also shows whether `response-content-disposition` is present — which is the whole
question for the download tests below.

## Step 1 — Launch

Revision `test/PLAT-5733-gcs-v4-signing`, your GCP Batch CE, `outdir` set to a `gs://` path in the
Data-Linked bucket. Wait for all four tasks green.

## Step 2 — Confirm V4 on genomic files

Open `sample.bam`, search a locus (`chr1:999,900-1,001,200`) to force the index fetch.

- ✅ `.bai` → **200**, `.bam` → **206**, URLs carry `X-Goog-Signature`, requests go to
  `storage.googleapis.com/<bucket>/<object>` (XML API)
- ❌ `.bai` → **401** `Anonymous caller…`, or URL rewritten to `/storage/v1/b/…&alt=media` → the V2
  bug is still present

Repeat for `variants.vcf.gz`.

## Step 3 — Confirm V2 is retained for non-genomic files

Open `report.txt`, `data.csv`, and `report.html`.

- ✅ Each previews correctly, and `generate-download-url` returns a **V2** URL
  (`GoogleAccessId`/`Signature`) **with** `response-content-disposition` present
- ❌ A V4 URL here means the classification is over-broad and the download/inline-preview params
  were dropped for ordinary files

## Step 4 — The download regression check (the novel test)

For each of `features.bed`, `variants.vcf`, `annotations.gtf`, `reference.fasta`, click **Download**
and record what actually happens:

- Does the file download, or open in a browser tab?
- If it downloads, is the filename correct?
- Confirm the signed URL has **no** `response-content-disposition`

Then do the same for `report.txt` as a control — it should download with the correct filename via
the V2 path.

**There is no single "correct" answer to assert here.** The PR authors accepted dropping those params
on the grounds that igv.js doesn't need them. This step establishes whether that trade-off also
changed the *download* experience for text-based genomic files. If a `.bed` now opens in a tab
instead of saving, that's a real UX regression worth reporting — not a blocker for the IGV fix, but
worth a follow-up.

The outcome depends on each object's stored `Content-Type`: with no `Content-Disposition`, an
`application/octet-stream` object still downloads while a `text/plain` one renders inline. Check
with:

```
gcloud storage objects describe gs://<bucket>/<prefix>/features.bed --format="value(content_type)"
```

## Step 5 — Sanity-check the untouched path

Confirm downloads and image/text previews for non-genomic files still behave as before. This is the
blast radius of the change: everything that isn't on the genomic suffix list should be bit-identical
in behaviour to pre-patch.

## Note on overlap with #11324

Verifying #11324 on this instance already produced V4 evidence — `X-Goog-Algorithm`/`X-Goog-Signature`
on the XML API endpoint with 200/206 responses. That is this PR's fix working. Step 2 re-confirms it
deliberately; Steps 3–5 are the parts that verification did **not** cover.
