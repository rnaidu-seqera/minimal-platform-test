#!/usr/bin/env nextflow

// FD-7399 — Scenario A: publishDir (old syntax, expected baseline)
// Files should appear in Seqera Platform Reports tab via tower.yml

params.sample = "sample1"

process MAKE_REPORT {
    container 'ubuntu:24.04'
    publishDir "${params.outdir}/reports", mode: 'copy'

    output:
    path "report.html", emit: html
    path "summary.csv", emit: csv

    script:
    """
    cat << 'EOF' > report.html
    <!DOCTYPE html>
    <html>
    <head><title>Pipeline Report</title></head>
    <body>
      <h1>Pipeline Report</h1>
      <p>Sample: ${params.sample}</p>
      <p>Status: complete</p>
    </body>
    </html>
    EOF

    printf 'sample,status\n${params.sample},complete\n' > summary.csv
    """
}

workflow {
    MAKE_REPORT()
}
