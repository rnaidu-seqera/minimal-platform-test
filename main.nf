#!/usr/bin/env nextflow

// FD-7531 — demonstrate that Seqera Platform merges the CE-level
// nextflow.config with the pipeline-level nextflow.config at runtime.
//
// Two processes:
//   BASE_DEFAULTS — receives all of its directives from the CE config.
//                   Used to prove the CE config is applied at all.
//   OVERRIDE_ME   — targeted by a `withName:` selector in the pipeline
//                   nextflow.config. Used to prove that the selector
//                   only overrides the keys it sets, and that the
//                   other CE-level process directives are preserved.

process BASE_DEFAULTS {
    debug     true
    container 'ubuntu:24.04'

    script:
    """
    echo "=== BASE_DEFAULTS (no pipeline override) ==="
    echo "task.cpus            = ${task.cpus}"
    echo "task.ext.from_ce     = ${task.ext.from_ce}"
    echo "task.ext.shared_key  = ${task.ext.shared_key}"
    echo "task.workDir         = ${task.workDir}"
    echo "pwd                  = \$(pwd)"
    """
}

process OVERRIDE_ME {
    debug     true
    container 'ubuntu:24.04'

    script:
    """
    echo "=== OVERRIDE_ME (targeted by pipeline withName: selector) ==="
    echo "task.cpus            = ${task.cpus}"
    echo "task.ext.from_ce     = ${task.ext.from_ce}"
    echo "task.ext.shared_key  = ${task.ext.shared_key}"
    echo "task.workDir         = ${task.workDir}"
    echo "pwd                  = \$(pwd)"
    """
}

workflow {
    BASE_DEFAULTS()
    OVERRIDE_ME()
}
