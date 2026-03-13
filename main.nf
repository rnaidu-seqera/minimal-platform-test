#!/usr/bin/env nextflow

params.greeting = "Hello"
params.name     = "World"

process SAY_HELLO {
    debug true

    input:
    val greeting
    val name

    script:
    """
    echo "${greeting}, ${name}!"
    """
}

workflow {
    SAY_HELLO(params.greeting, params.name)
}
