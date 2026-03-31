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
    echo '<!DOCTYPE html>'                          >  report.html
    echo '<html><head><title>Pipeline Report</title></head><body>' >> report.html
    echo '<h1>Pipeline Report</h1>'                >> report.html
    echo '<p>Sample: ${params.sample}</p>'         >> report.html
    echo '<p>Status: complete</p></body></html>'   >> report.html

    echo 'sample,status'                           >  summary.csv
    echo '${params.sample},complete'               >> summary.csv
    """
}

workflow {
    MAKE_REPORT()
}
