#!/usr/bin/env nextflow

// FD-7399 — Scenario B: new workflow output syntax
// Tests whether tower.yml reports still appear when using output {} instead of publishDir

params.sample = "sample1"

process MAKE_REPORT {
    container 'ubuntu:24.04'

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
    main:
    MAKE_REPORT()

    publish:
    html = MAKE_REPORT.out.html
    csv  = MAKE_REPORT.out.csv
}

output {
    html {
        path 'reports'
    }
    csv {
        path 'reports'
    }
}
