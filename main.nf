#!/usr/bin/env nextflow

/*
 * MRE for FD-7749 / PR seqeralabs/platform#11971 — "sign IGV reference genome URLs"
 *
 * `IgvConfigService.resolveConfig$` only signed *track* URLs, so a custom reference genome in a
 * private bucket was handed to igv.js unsigned and the browser's fetch was rejected. Two gaps:
 *
 *   1. Reference-only configs were skipped outright — `if (!config.tracks?.length) return of(config)`
 *      bailed early, and a config registering a custom genome is exactly that shape.
 *   2. `collectUniqueUrls` walked `tracks` only, so `reference.*` URLs went unsigned even when
 *      tracks were present.
 *
 * This is reachable ONLY through the JSON-config path: a user-authored IGV config opened in Data
 * Explorer. Opening a FASTA directly is a different code path (#11324), so the fixtures here are
 * config files plus a small synthetic genome for them to point at.
 *
 * The four configs isolate one thing each:
 *
 *   genome-only.json          reference, no tracks         -> gap 1 (early return removed)
 *   genome-with-track.json    reference + session tracks   -> gap 2 (reference collected anyway)
 *   genome-nested-tracks.json reference.tracks             -> genome-level tracks also signed
 *   genome-chromsizes.json    reference.chromSizesURL      -> a REFERENCE_URL_FIELDS entry the
 *                                                            bundled igv typings omit
 *
 * The genome is a synthetic 10 kb contig named `chrTest` so it cannot be confused with a built-in
 * genome — if the reference fails to load, nothing renders at all, which is the signal we want.
 *
 * IMPORTANT: `params.outdir` is baked into the config files as absolute URLs, so it must be the
 * final cloud location (gs://… or az://…), not a relative path. See README.md.
 */

params.outdir = 'results'

process MAKE_REFERENCE {
    publishDir params.outdir, mode: 'copy'
    container 'quay.io/biocontainers/samtools:1.21--h50ea8bc_0'

    output:
    tuple path('reference.fasta'), path('reference.fasta.fai'), path('chrTest.chrom.sizes')

    script:
    '''
    # 10 kb single contig, 60-char lines (samtools faidx requires uniform line length).
    LINE=ACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGT
    {
        printf '>chrTest synthetic test contig\\n'
        for i in $(seq 1 166); do printf '%s\\n' "$LINE"; done
        printf 'ACGTACGTACGTACGTACGTACGTACGTACGTACGTACGT\\n'
    } > reference.fasta

    samtools faidx reference.fasta

    # chrom.sizes for the chromSizesURL config case.
    printf 'chrTest\\t10000\\n' > chrTest.chrom.sizes

    test -s reference.fasta.fai
    grep -q '^chrTest' reference.fasta.fai
    '''
}

process MAKE_TRACKS {
    publishDir params.outdir, mode: 'copy'
    container 'quay.io/biocontainers/samtools:1.21--h50ea8bc_0'

    output:
    tuple path('sample.bam'), path('sample.bam.bai'), path('features.bed')

    script:
    '''
    SEQ=ACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTAC
    QUAL=IIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIII

    # Aligned to chrTest, not hg38 — these only render if the custom reference loaded.
    {
        printf '@HD\\tVN:1.6\\tSO:coordinate\\n'
        printf '@SQ\\tSN:chrTest\\tLN:10000\\n'
        for i in $(seq 1 100); do
            pos=$(( 1000 + i * 5 ))
            printf 'read%d\\t0\\tchrTest\\t%d\\t60\\t50M\\t*\\t0\\t0\\t%s\\t%s\\n' "$i" "$pos" "$SEQ" "$QUAL"
        done
    } > sample.sam

    samtools view -b -o sample.unsorted.bam sample.sam
    samtools sort -o sample.bam sample.unsorted.bam
    samtools index sample.bam

    for i in $(seq 1 10); do
        start=$(( 3000 + i * 50 ))
        end=$(( start + 25 ))
        printf 'chrTest\\t%d\\t%d\\tfeature%d\\t0\\t+\\n' "$start" "$end" "$i"
    done > features.bed

    samtools quickcheck -v sample.bam
    test -s features.bed
    '''
}

process MAKE_IGV_CONFIGS {
    publishDir params.outdir, mode: 'copy'
    // python for the JSON validity check below; the samtools image has no interpreter.
    container 'python:3.12-slim'

    output:
    path '*.json'

    script:
    // Absolute cloud URLs, baked in at generation time. These are the URLs the PR must sign.
    def base = params.outdir
    """
    cat > genome-only.json <<'JSON'
    {
      "reference": {
        "id": "chrTest-genome",
        "name": "Synthetic test genome (reference only)",
        "fastaURL": "${base}/reference.fasta",
        "indexURL": "${base}/reference.fasta.fai"
      }
    }
    JSON

    cat > genome-with-track.json <<'JSON'
    {
      "reference": {
        "id": "chrTest-genome",
        "name": "Synthetic test genome (with session track)",
        "fastaURL": "${base}/reference.fasta",
        "indexURL": "${base}/reference.fasta.fai"
      },
      "tracks": [
        {
          "name": "Alignments",
          "type": "alignment",
          "format": "bam",
          "url": "${base}/sample.bam",
          "indexURL": "${base}/sample.bam.bai"
        }
      ]
    }
    JSON

    cat > genome-nested-tracks.json <<'JSON'
    {
      "reference": {
        "id": "chrTest-genome",
        "name": "Synthetic test genome (genome-level tracks)",
        "fastaURL": "${base}/reference.fasta",
        "indexURL": "${base}/reference.fasta.fai",
        "tracks": [
          {
            "name": "Genome annotations",
            "type": "annotation",
            "format": "bed",
            "url": "${base}/features.bed"
          }
        ]
      }
    }
    JSON

    cat > genome-chromsizes.json <<'JSON'
    {
      "reference": {
        "id": "chrTest-genome",
        "name": "Synthetic test genome (chromSizesURL)",
        "fastaURL": "${base}/reference.fasta",
        "indexURL": "${base}/reference.fasta.fai",
        "chromSizesURL": "${base}/chrTest.chrom.sizes"
      }
    }
    JSON

    # A config that fails to parse degrades silently to the text viewer, so validity is
    # load-bearing for this test. Fail the task rather than discover it in the browser.
    for f in *.json; do
        python3 -c "import json,sys; json.load(open(sys.argv[1]))" "\$f" || exit 1
    done
    """
}

workflow {
    MAKE_REFERENCE()
    MAKE_TRACKS()
    MAKE_IGV_CONFIGS()
}
