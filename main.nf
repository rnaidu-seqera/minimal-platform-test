#!/usr/bin/env nextflow

/*
 * MRE for PLAT-5733 / PR seqeralabs/platform#11624 — "sign GCS genomic file URLs with V4"
 *
 * Platform now signs GCS URLs for *genomic* files with a V4 signature, because igv.js only treats
 * a URL as signed if it carries `X-Goog-Signature`. Given a V2 URL it rewrote the request to the
 * GCS JSON API endpoint, which ignores query-string signatures and 401s as an anonymous caller.
 *
 * The V4 path takes an early `return url` and therefore drops `response-content-disposition` and
 * `response-content-type`. Every non-genomic file keeps V2 with those params appended as before.
 * So the change splits Data Explorer's signing into two paths, and this pipeline publishes fixtures
 * on both sides of that split — including text-based genomic formats, where losing the
 * `attachment` disposition is most likely to change browser behaviour.
 *
 * Classification comes from GENOMIC_FILE_SUFFIXES in GoogleDataLinkClient. Note `.bed`, `.vcf`,
 * `.gtf` and `.fasta` are all on the genomic (V4) side despite being plain text.
 *
 *   V4 expected, binary   sample.bam, sample.bam.bai, variants.vcf.gz, variants.vcf.gz.tbi
 *   V4 expected, TEXT     variants.vcf, features.bed, annotations.gtf, reference.fasta
 *   V2 expected           report.txt, data.csv, report.html
 *
 * See README.md for the launch and verification steps.
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

process MAKE_VCF_PAIR {
    publishDir params.outdir, mode: 'copy'
    container 'quay.io/biocontainers/htslib:1.21--h566b1c6_1'

    output:
    // Both the compressed+indexed pair and the plain-text .vcf: `.vcf` is on the genomic list too,
    // so it gets V4 and loses its download disposition despite being human-readable text.
    tuple path('variants.vcf'), path('variants.vcf.gz'), path('variants.vcf.gz.tbi')

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

process MAKE_TEXT_GENOMIC {
    publishDir params.outdir, mode: 'copy'
    container 'quay.io/biocontainers/samtools:1.21--h50ea8bc_0'

    output:
    tuple path('features.bed'), path('annotations.gtf'), path('reference.fasta')

    script:
    '''
    # All three are plain text but classified genomic, so all three take the V4 path and lose
    # `Content-Disposition: attachment`. These are the download-behaviour test cases.
    for i in $(seq 1 10); do
        start=$(( 1000000 + i * 100 ))
        end=$(( start + 50 ))
        printf 'chr1\\t%d\\t%d\\tfeature%d\\t0\\t+\\n' "$start" "$end" "$i"
    done > features.bed

    for i in $(seq 1 10); do
        start=$(( 1000000 + i * 100 ))
        end=$(( start + 50 ))
        printf 'chr1\\ttest\\texon\\t%d\\t%d\\t.\\t+\\t.\\tgene_id "gene%d"; transcript_id "tx%d";\\n' \\
            "$start" "$end" "$i" "$i"
    done > annotations.gtf

    {
        printf '>chr1 test sequence\\n'
        for i in $(seq 1 20); do
            printf 'ACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTAC\\n'
        done
    } > reference.fasta

    test -s features.bed && test -s annotations.gtf && test -s reference.fasta
    '''
}

process MAKE_NON_GENOMIC {
    publishDir params.outdir, mode: 'copy'
    container 'quay.io/biocontainers/samtools:1.21--h50ea8bc_0'

    output:
    tuple path('report.txt'), path('data.csv'), path('report.html')

    script:
    '''
    # Control group: none of these suffixes are on GENOMIC_FILE_SUFFIXES, so they must keep the V2
    # signature with response-content-disposition / response-content-type appended.
    printf 'PLAT-5733 control file.\\nThis must stay on the V2 signing path.\\n' > report.txt

    {
        printf 'sample,count,value\\n'
        for i in $(seq 1 10); do
            printf 'sample%d,%d,%d.5\\n' "$i" "$(( i * 10 ))" "$i"
        done
    } > data.csv

    {
        printf '<!DOCTYPE html>\\n<html><head><title>PLAT-5733 control</title></head>\\n'
        printf '<body><h1>V2 signing path</h1>\\n'
        printf '<p>Should render inline via response-content-type.</p></body></html>\\n'
    } > report.html

    test -s report.txt && test -s data.csv && test -s report.html
    '''
}

workflow {
    MAKE_INDEXED_BAM()
    MAKE_VCF_PAIR()
    MAKE_TEXT_GENOMIC()
    MAKE_NON_GENOMIC()
}
