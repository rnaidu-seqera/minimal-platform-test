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

## 3. Housekeeping in rashmi-project-sandbox

- Bucket CORS on `rashmi-project-sandbox-batch-work` currently uses `"origin": ["*"]`. Tighten to
  `https://enterprise.stage-tower.net` or remove once IGV testing is done.
- `gs://rashmi-project-sandbox-batch-work/igv-mre/.keep` placeholder can be deleted.
- `roles/storage.legacyBucketReader` grant on that bucket is read-only metadata; harmless to leave.

## 4. Open for PR #11324 sign-off

Build version of the instance under test was never recorded. Needed to anchor the verification.
