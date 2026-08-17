# Follow-ups from 26.1.5 patch verification

Parked 2026-08-17 to finish verifying the remaining two PRs first. Revisit before escalating.

## 1. Misleading IGV error — filed, needs revisiting

**https://github.com/seqeralabs/platform/issues/12145** — IGV preview reports CORS/network
failures as a Google OAuth error. Scoped to the error message only.

Filed as a first pass. Revisit after the other two PRs in case they surface related UI-error
problems worth consolidating into one report.

Verified fact worth keeping: the string is **upstream igv.js**, present verbatim in the published
`igv` dist bundle including the `initalized` typo. Platform cannot reword it — it has to intercept
before igv.js reports it.

## 2. EDU docs ticket — not yet filed

Needs a Jira EDU ticket. Draft:

**Summary:** Document cloud storage prerequisites for Data Explorer IGV previews

**Description:** Two setup requirements for previewing genomic files in Data Explorer are
undocumented. Both blocked verification of a 26.1.5 patch on an otherwise correctly configured GCP
instance, and both produce errors that point away from the real cause.

**(a) Buckets require a CORS policy.** IGV fetches index and data chunks directly from cloud storage
via cross-origin range requests. Without CORS the browser blocks them and igv.js misreports it as a
Google OAuth failure (see platform#12145). `Range` must be among the exposed response headers or the
preflight fails. GCS example:

```json
[{
  "origin": ["https://<platform-host>"],
  "method": ["GET", "HEAD"],
  "responseHeader": ["Range", "Content-Type", "Content-Length",
                     "Content-Range", "Accept-Ranges", "ETag"],
  "maxAgeSeconds": 3600
}]
```

**(b) `roles/storage.objectAdmin` is insufficient to create a GCS Data Link.** It omits
`storage.buckets.get`, so Batch jobs run fine while Data Link creation fails with
`Insufficient permissions to access bucket`. Fix: `roles/storage.legacyBucketReader` on the bucket,
or `roles/storage.bucketViewer` at project level if bucket auto-discovery is also wanted (that role
carries `storage.buckets.list` and holds only those two permissions).

**Acceptance criteria:** Data Explorer setup docs state the CORS requirement with a copy-pasteable
example per provider and call out the `Range` header; the GCS permissions section lists
`storage.buckets.get` as required for Data Links.

## 3. NEW FINDING — platform#11624 breaks Download for text-based genomic files

Found 2026-08-17 while verifying #11624 on GCP. **The PR's own fix works**; this is a side effect of
it, not a reason to hold the patch.

`buildPresignedUrl` returns early for genomic files, dropping `response-content-disposition`.
`GENOMIC_FILE_SUFFIXES` includes plain-text formats — `.bed`, `.vcf`, `.gtf`, `.gff`, `.gff3`,
`.wig`, `.bedgraph`, `.fasta`, `.fa` — so clicking **Download** on any of these serves the object
with no `Content-Disposition`. When the object has a text `Content-Type`, the browser renders it in
a tab instead of saving it.

**Controlled reproduction.** Two objects, both `Content-Type: text/plain`, differing only in signing
path:

| Object | Path | `Content-Disposition` | Download result |
| --- | --- | --- | --- |
| `features-typed.bed` | genomic → V4 | absent | opens in a new tab |
| `report-typed.txt` | non-genomic → V2 | `attachment; filename=…` | saves to disk |

Both live at `gs://rashmi-project-sandbox-batch-work/v4-mre/`.

**Not affected:** binary genomic formats (`.bam`, `.cram`, `.bai`, `.tbi`, `.bigwig`, `.2bit`) — they
download regardless because browsers save `application/octet-stream`. Also not reproducible on objects
with no `Content-Type` set at all, which is why the pipeline-published fixtures didn't reveal it; GCS
defaults those to `application/octet-stream`. Customer buckets populated via the console or `gsutil`
**do** get text content types by extension, so this is reachable in practice.

**Severity:** moderate UX regression, no data loss or security impact. Workaround is right-click →
Save As.

**Suggested fix — gate V4 on the preview path only.** `buildPresignedUrl` already takes a `preview`
flag. igv.js only needs V4 when *previewing*; the Download button doesn't involve igv.js at all. So
`isGenomicFile(uri) && preview` → V4 without params, everything else → V2 with params appended.
Fixes the regression with no dependency bump. The alternative — upgrading
`google-cloud-storage` to 2.x for `withQueryParams` so the `response-content-*` params can be
included in the V4 signature — is cleaner but is exactly what the PR set out to avoid.

Needs confirming that the IGV preview path always passes `preview=true` before proposing this.

## 4. Release-note line for 26.1.5 — time-sensitive

Most urgent item here, because release notes get finalised on a deadline the others don't have.

After #11624, GCS buckets require a CORS policy exposing `Range` for Data Explorer IGV previews to
work. Nobody loses functionality — GCS previews were broken (401) before the patch — but customers
upgrading and expecting working previews will hit the misleading `Google oAuth has not been
initalized` error (see item 1) with no obvious cause. Support will field these as "IGV is broken".

One line in the 26.1.5 notes plus the EDU docs page (item 2) pre-empts that.

## 5. Housekeeping in rashmi-project-sandbox

- Bucket CORS on `rashmi-project-sandbox-batch-work` currently uses `"origin": ["*"]`. Tighten to
  `https://enterprise.stage-tower.net` or remove once IGV testing is done.
- `gs://rashmi-project-sandbox-batch-work/igv-mre/.keep` placeholder can be deleted.
- `roles/storage.legacyBucketReader` grant on that bucket is read-only metadata; harmless to leave.

## 6. Build version under test — RESOLVED

**`26.1.5-RC_8da22c0`** (read from the Platform UI footer, 2026-08-17).

All verification in this document was performed against that build on `enterprise.stage-tower.net`,
workspace `test-org / test-workspace`, GCP Batch CE `gcp-test-ce`.
