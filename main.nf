#!/usr/bin/env nextflow

/*
 * MRE for PLAT-5421 / PR seqeralabs/platform#11324 — "fix(ui): presign indexURLs independently"
 *
 * The PR fixes the IGV viewer deriving an index companion's URL by string-appending the index
 * extension to the *data* file's presigned URL, reusing its signature. A presigned cloud URL is
 * bound to a single object key, so the derived `.bai` URL is rejected by the storage backend and
 * IGV errors once it actually needs the index (i.e. when you zoom in far enough to fetch a region).
 *
 * This pipeline produces nothing but genomic fixtures, so that the four code paths the PR touches
 * each have a file to exercise in Data Explorer:
 *
 *   sample.bam + sample.bam.bai   data file with a real index    -> both signed independently
 *   unindexed.bam (no .bai)       index companion is missing     -> track marked `indexed: false`
 *   variants.vcf.gz + .tbi        a second indexed format        -> same independent signing
 *   features.bed                  format with no known index     -> no `indexed` flag at all
 *
 * Coordinates are hg38-compatible (chr1) so the default genome in the viewer lines up and the
 * reads render where you zoom to. See README.md for the launch and verification steps.
 */

params.outdir = 'results'

process MAKE_INDEXED_BAM {
    publishDir params.outdir, mode: 'copy'
    container 'quay.io/biocontainers/samtools:1.21--h50ea8bc_0'

    output:
    tuple path('sample.bam'), path('sample.bam.bai')

    script:
    '''
    SEQ=ACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTAC
    QUAL=IIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIII

    # 200 reads tiled across chr1:1,000,000-1,001,000 give visible coverage at max zoom,
    # which is what forces IGV to do an indexed range request.
    {
        printf '@HD\\tVN:1.6\\tSO:coordinate\\n'
        printf '@SQ\\tSN:chr1\\tLN:248956422\\n'
        for i in $(seq 1 200); do
            pos=$(( 1000000 + i * 5 ))
            printf 'read%d\\t0\\tchr1\\t%d\\t60\\t50M\\t*\\t0\\t0\\t%s\\t%s\\n' "$i" "$pos" "$SEQ" "$QUAL"
        done
    } > sample.sam

    samtools view -b -o sample.unsorted.bam sample.sam
    samtools sort -o sample.bam sample.unsorted.bam
    samtools index sample.bam

    samtools quickcheck -v sample.bam
    test -s sample.bam.bai
    '''
}

process MAKE_UNINDEXED_BAM {
    publishDir params.outdir, mode: 'copy'
    container 'quay.io/biocontainers/samtools:1.21--h50ea8bc_0'

    output:
    path 'unindexed.bam'

    script:
    '''
    SEQ=ACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTAC
    QUAL=IIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIII

    # Deliberately NOT indexed: this is the "companion cannot be signed" case. Pre-patch the UI
    # derived a bogus .bai URL and IGV errored; post-patch the track is marked unindexed instead.
    {
        printf '@HD\\tVN:1.6\\tSO:coordinate\\n'
        printf '@SQ\\tSN:chr1\\tLN:248956422\\n'
        for i in $(seq 1 50); do
            pos=$(( 2000000 + i * 5 ))
            printf 'read%d\\t0\\tchr1\\t%d\\t60\\t50M\\t*\\t0\\t0\\t%s\\t%s\\n' "$i" "$pos" "$SEQ" "$QUAL"
        done
    } > unindexed.sam

    samtools view -b -o unindexed.unsorted.bam unindexed.sam
    samtools sort -o unindexed.bam unindexed.unsorted.bam

    samtools quickcheck -v unindexed.bam
    # Guard the intent of this fixture: an accidental .bai would silently void the test case.
    test ! -e unindexed.bam.bai
    '''
}

process MAKE_INDEXED_VCF {
    publishDir params.outdir, mode: 'copy'
    container 'quay.io/biocontainers/htslib:1.21--h566b1c6_1'

    output:
    tuple path('variants.vcf.gz'), path('variants.vcf.gz.tbi')

    script:
    '''
    {
        printf '##fileformat=VCFv4.2\\n'
        printf '##contig=<ID=chr1,length=248956422>\\n'
        printf '##INFO=<ID=DP,Number=1,Type=Integer,Description="Total Depth">\\n'
        printf '#CHROM\\tPOS\\tID\\tREF\\tALT\\tQUAL\\tFILTER\\tINFO\\n'
        for i in $(seq 1 40); do
            pos=$(( 1000000 + i * 25 ))
            printf 'chr1\\t%d\\tvar%d\\tA\\tG\\t50\\tPASS\\tDP=30\\n' "$pos" "$i"
        done
    } > variants.vcf

    bgzip -c variants.vcf > variants.vcf.gz
    tabix -p vcf variants.vcf.gz

    test -s variants.vcf.gz.tbi
    '''
}

process MAKE_PLAIN_BED {
    publishDir params.outdir, mode: 'copy'
    container 'quay.io/biocontainers/samtools:1.21--h50ea8bc_0'

    output:
    path 'features.bed'

    script:
    '''
    # Plain .bed has no entry in the UI's index-extension map, so the fixed code should emit
    # neither an indexURL nor an `indexed` flag. Only `.bed.gz` pairs with a `.tbi`.
    for i in $(seq 1 10); do
        start=$(( 1000000 + i * 100 ))
        end=$(( start + 50 ))
        printf 'chr1\\t%d\\t%d\\tfeature%d\\t0\\t+\\n' "$start" "$end" "$i"
    done > features.bed

    test -s features.bed
    '''
}

workflow {
    MAKE_INDEXED_BAM()
    MAKE_UNINDEXED_BAM()
    MAKE_INDEXED_VCF()
    MAKE_PLAIN_BED()
}
