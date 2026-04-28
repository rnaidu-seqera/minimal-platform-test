# minimal-platform-test

Minimal Nextflow pipeline to reproduce the Seqera Platform parameter type-coercion issue reported in **FD-7482**.

## The Problem

`call_min_reads` is declared as `type: string` in `nextflow_schema.json` because it accepts either a bare integer (`1`) or a comma-separated list of up to three integers (`1,1,1`). Seqera Platform coerces integer-looking string values to JSON integers before launching, which:

1. Causes `nf-schema` validation to fail (`Expected string, got integer`).
2. Prevents resume: the Platform strips any manually added quotes from the value in the parameter form, so there is no way to force the value back to a string through the UI.

## Pipeline Structure

```
main.nf                  # Prints the param value and its Groovy type
nextflow.config          # Enables nf-schema plugin; sets default call_min_reads = "1"
nextflow_schema.json     # Declares call_min_reads as type: string with pattern validation
```

## Local Test — Confirming the Pipeline Works Correctly

Run these commands to verify both valid string forms pass nf-schema validation locally:

```bash
# Single value — works
nextflow run . --call_min_reads 1

# Comma-separated list — works
nextflow run . --call_min_reads "1,1,1"
```

Expected output in both cases:

```
call_min_reads value : '1'          (or '1,1,1')
Groovy type          : String
```

## Reproducing the Platform Bug

### Step 1 — Launch the pipeline

1. Add this repo as a Pipeline in Seqera Platform.
2. Create a new Run with **call_min_reads = 1** (type the bare digit, no quotes).
3. Launch. The run should succeed and the log should show `Groovy type: String`.

> **Observe**: In the Run parameters panel the value may already be shown as the integer `1`, not the string `"1"`.

### Step 2 — Trigger the validation error on Resume

1. Open the completed run and click **Resume**.
2. The parameter form will show `call_min_reads = 1`.
3. Click Launch without editing — the run may fail with an nf-schema error like:
   ```
   ERROR ~ Validation of pipeline parameters failed!
   * --call_min_reads (1): Value is not of type 'string'
   ```

### Step 3 — Confirm the quote-stripping behaviour

1. On the Resume form, manually change the value to `"1"` (with quotes).
2. Observe that the Platform strips the quotes and saves it as `1` (integer).
3. Launch — the same validation error occurs.

## Expected vs Actual Behaviour

| | Expected | Actual |
|---|---|---|
| Schema type | `string` respected | Coerced to integer for numeric-looking values |
| Resume parameter form | Shows `"1"` (string) | Shows `1` (integer) |
| Manual quoting | Preserved | Stripped by Platform |

## Related

- FreshDesk ticket: FD-7482
- nf-core/fastquorum pipeline (original reporter's context)
- nf-schema plugin: https://nextflow-io.github.io/nf-schema/
