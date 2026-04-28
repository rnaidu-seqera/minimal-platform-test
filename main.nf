#!/usr/bin/env nextflow

params.call_min_reads = "1"

include { validateParameters } from 'plugin/nf-schema'

process SHOW_PARAM_TYPE {
    debug true

    script:
    """
    echo "call_min_reads value : '${params.call_min_reads}'"
    echo "Groovy type          : ${params.call_min_reads.getClass().simpleName}"
    """
}

workflow {
    validateParameters()
    SHOW_PARAM_TYPE()
}
