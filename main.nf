#!/usr/bin/env nextflow

params.greeting = "Hello"
params.name     = "World"
params.count    = null

process SAY_HELLO {
    container 'ubuntu:22.04'
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
