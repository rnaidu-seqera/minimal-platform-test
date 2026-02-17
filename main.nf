#!/usr/bin/env nextflow

/*
 * FD-7263: Template directive display issue in Seqera Platform
 *
 * This MRE demonstrates the issue where Platform shows template('script.py')
 * instead of the actual resolved command content
 */

params.input = "sample_data.txt"

workflow {
    // Create a simple input channel
    input_ch = Channel.of(
        ['sample1', 'ATCGATCG'],
        ['sample2', 'GCTAGCTA'],
        ['sample3', 'TTAACCGG']
    )

    // Run process using template directive
    ANALYZE_WITH_TEMPLATE(input_ch)

    ANALYZE_WITH_TEMPLATE.out.view { id, result ->
        "Sample $id: ${result.text.trim()}"
    }
}

/*
 * Process using template directive
 * This should show template('analyze.py') in Platform instead of the actual script
 */
process ANALYZE_WITH_TEMPLATE {
    tag "$sample_id"

    input:
    tuple val(sample_id), val(sequence)

    output:
    tuple val(sample_id), path("${sample_id}_result.txt")

    script:
    template 'analyze.py'
}
