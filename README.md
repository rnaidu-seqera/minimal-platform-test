# MRE — PLAT-5421 / platform#11324: presign indexURLs independently

Tests `fix(ui): presign indexURLs independently` (label `enterprise/26.1.5`) on a Seqera Platform
Enterprise instance using a GCP Batch compute environment.

## What the PR actually changes

This is a **front-end fix**, not a Nextflow feature. Nothing about pipeline *execution* changes — the
pipeline here exists only to put the right genomic fixtures into a GCS bucket so the viewer has
something to render.

**The bug.** When the IGV viewer previewed a genomic file, it built the index companion's URL by
string-appending the index extension to the *data* file's presigned URL and **reusing that URL's
query string** — i.e. the BAM's signature:

```
url      = https://storage.googleapis.com/bucket/sample.bam?X-Goog-Signature=SIG_FOR_BAM
indexURL = https://storage.googleapis.com/bucket/sample.bam.bai?X-Goog-Signature=SIG_FOR_BAM   <-- invalid
```

A presigned cloud URL is cryptographically bound to a single object key, so the derived `.bai` URL is
rejected by the storage backend. The failure is **lazy**: IGV only fetches the index once it needs a
specific region, which is why you have to zoom in to see it.

**The fix.** `partitionGenomicPath()` infers the sibling path, each URL is signed for its own key, and
both are handed to `generateConfig({ url, indexURL, deriveIndex: false })` so the unsafe derivation is
suppressed. When the index genuinely can't be signed (it doesn't exist), the track gets
`indexed: false` so IGV doesn't error trying to load one.

**Two surfaces changed** — test both:

| Surface | File in PR |
| --- | --- |
| Data Explorer file preview dialog | `data-explorer-file-preview-dialog.component.ts` |
| Run **Reports** tab (workflow outputs) | `workflow-launch-reports.component.ts` |

The Reports-tab path is *new* behavior: it previously only used the Tower `/content/redirect/…` path,
and now resolves cloud-scheme paths against DataLinks and signs both companions, falling back to the
Tower path when no DataLink covers the bucket.

## Fixtures this pipeline produces

Each one targets a distinct branch of the changed code. Coordinates are hg38-compatible (`chr1`) so
the default genome lines up and reads render where you zoom.

| File | Case exercised | Expected post-patch |
| --- | --- | --- |
| `sample.bam` + `sample.bam.bai` | data file with a real index | both signed independently; alignments render at max zoom |
| `unindexed.bam` (no `.bai`) | index companion missing | track marked `indexed: false`; preview still opens, no error toast |
| `variants.vcf.gz` + `.tbi` | a second indexed format | same independent signing |
| `features.bed` | format with **no** known index | no `indexURL` and no `indexed` flag emitted |

## Prerequisites

1. GCP Batch compute environment configured in the workspace.
2. The GCP credentials backing that CE can read/write the bucket you'll publish to.
3. **A Data Link covering that bucket.** This is the part most likely to bite you on a clean
   instance — the Reports-tab signing path requires `resolveUrls$` to match the `gs://` path against a
   DataLink, and Data Explorer needs it to list the files at all. Platform auto-discovers buckets from
   workspace credentials; confirm the bucket appears under **Data Explorer** before launching.

## Step 1 — Launch the run

1. Add this repo as a pipeline (or use **Launch → Start quick launch**).
2. Set **Revision** to `test/PLAT-5421-igv-index-presign`.
3. Select your **GCP Batch** compute environment.
4. Set **outdir** to a `gs://` path in the bucket from the prerequisites, e.g.
   `gs://<your-bucket>/igv-mre`. **Do not leave it as `results`** — a relative path publishes inside
   the work directory and may not be covered by a Data Link.
5. Launch. Four short tasks; expect a couple of minutes, mostly image pull.

Confirm all four tasks succeeded before interpreting anything below — the process bodies assert their
own outputs (`samtools quickcheck`, `test -s …`), so a green run means the fixtures are valid and
`unindexed.bam` really has no index.

## Step 2 — Verify in Data Explorer (primary surface)

This mirrors the PR's own test plan.

1. **Data Explorer** → your bucket → `igv-mre/`.
2. Click `sample.bam` to open the preview dialog. The IGV viewer should render.
3. **Zoom in to trigger the indexed read.** Type `chr1:999,900-1,001,200` into the locus box and press
   enter (or click the chromosome ideogram and use the zoom bar top-right). The 200 reads should appear
   as a stacked pileup.
   - ✅ **Fixed:** reads render, no error toast, no red banner in the track.
   - ❌ **Pre-patch:** the track errors when the index fetch is attempted — typically an error toast
     and/or an empty track, because the `.bai` request is rejected.
4. **Open the index directly.** Go back and click `sample.bam.bai`. The fix swaps the pair, so the
   viewer should render **the BAM**, not attempt to display the index as a data file. Zoom in again.
5. **Missing-index case.** Open `unindexed.bam`. The preview should open and render *something* without
   an error — the track is marked unindexed rather than trying to load a nonexistent `.bai`. This is
   the case that most clearly separates fixed from broken: pre-patch this errored, post-patch it
   degrades gracefully.
6. **Second format.** Open `variants.vcf.gz`, zoom to the same locus; the 40 variants should render.
7. **No-index format.** Open `features.bed`; the 10 features should render with no index involvement.

## Step 3 — The decisive check (browser devtools)

The UI signals above are suggestive; this one is objective. Before opening a preview, open devtools →
**Network**.

1. Open `sample.bam` and zoom in as above.
2. Find the two requests to `storage.googleapis.com` (or your signed-URL host) — one for `sample.bam`,
   one for `sample.bam.bai`.
3. **Compare their query strings.**
   - ✅ **Fixed:** the two URLs have **different** `X-Goog-Signature` values — each was signed for its
     own object key. The `.bai` request returns **200**.
   - ❌ **Pre-patch:** the signatures are **byte-identical** and the `.bai` request returns **403**
     with a `SignatureDoesNotMatch` XML body.
4. You should also see the signing roundtrip itself request **both** paths (`…/sample.bam` and
   `…/sample.bam.bai`) rather than just the one the user clicked.

Identical signatures on the two URLs means you are running unpatched code, regardless of whether the
track happened to render.

## Step 4 — Verify in the Reports tab (second surface)

1. Open the completed run → **Reports** tab.
2. The four fixtures should be listed with their display names.
3. Click each and repeat the zoom check from Step 2, plus the signature comparison from Step 3.

Two caveats here, in order of likelihood:

- **If a fixture is missing from the tab**, the report path glob didn't match. Report paths resolve
  relative to the launch directory, so the `**/…` globs in `nextflow.config` are deliberately loose,
  but they may still need adjusting for your work-directory layout. This is a limitation of my glob
  guess, not evidence about the PR.
- **If the URLs are Tower `/content/redirect/…` paths instead of signed `storage.googleapis.com`
  URLs**, you've hit the intentional fallback — it means no DataLink covered the `gs://` path, so the
  new signing code never ran. Fix the Data Link (see Prerequisites) and re-check, otherwise this
  surface tells you nothing about the fix.

## Notes

- Fixtures are synthetic and tiny (200 reads, 40 variants, 10 features) — enough to be visibly
  present at the target locus, small enough that the run is nearly free.
- `unindexed.bam` asserts `test ! -e unindexed.bam.bai` so an accidental index can't silently void
  that test case.
- Because this is a UI fix, a green pipeline run proves nothing on its own. All the signal is in
  Steps 2–4.
