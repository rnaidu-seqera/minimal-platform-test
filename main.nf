#!/usr/bin/env nextflow

process SAY_HELLO {
    output:
    path 'greeting.txt'

    script:
    """
    echo "${params.greeting}, ${params.name}!" > greeting.txt
    """
}

workflow {
    SAY_HELLO()
}
