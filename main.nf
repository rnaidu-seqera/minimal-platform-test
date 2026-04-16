#!/usr/bin/env nextflow

process SAY_HELLO {
    container 'ubuntu:24.04'

    output:
    path 'greeting.txt'

    script:
    """
    echo "${params.greeting}, ${params.name}!" > greeting.txt
    echo "TOWER_WORKFLOW_ID=${System.env.TOWER_WORKFLOW_ID ?: 'NOT SET'}" >> greeting.txt
    """
}

workflow {
    log.info "workflow.sessionId             = ${workflow.sessionId}"
    log.info "workflow.runName               = ${workflow.runName}"
    log.info "TOWER_WORKFLOW_ID              = ${System.env.TOWER_WORKFLOW_ID ?: 'NOT SET (running locally?)'}"
    log.info "workflow.platform.workflowId   = ${workflow.platform?.workflowId ?: 'NOT SET'}"

    SAY_HELLO()
}
