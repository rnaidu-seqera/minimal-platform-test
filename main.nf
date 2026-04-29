#!/usr/bin/env nextflow

// MRE for FD-7490: Fusion filesystem produces different results than non-Fusion
// for a process that renames files using shell globs + Python os.rename().

process CREATE_TEST_INPUTS {
    container 'python:3.9-slim'

    output:
    tuple val("TEST_SAMPLE"), path("*.fastq.gz")

    script:
    """
    printf '@READ1\\nACGT\\n+\\nIIII\\n' | gzip > SAMPLE_PH0001_R1_001.fastq.gz
    printf '@READ1\\nACGT\\n+\\nIIII\\n' | gzip > SAMPLE_PH0001_R2_001.fastq.gz
    printf '@READ1\\nACGT\\n+\\nIIII\\n' | gzip > SAMPLE_A001_R1_001.fastq.gz
    printf '@READ1\\nACGT\\n+\\nIIII\\n' | gzip > SAMPLE_A001_R2_001.fastq.gz
    """
}

process SCULPT {
    container 'python:3.9-slim'
    errorStrategy 'ignore'
    debug true

    input:
    tuple val(sample_id), path(sample)
    path scripts

    output:
    path("renamed/*"), optional: true

    script:
    """
    echo "=== [SCULPT] sample_id: ${sample_id} ==="
    echo "=== Files visible in work dir (ls -la) ==="
    ls -la
    echo "=== find -maxdepth 1 output ==="
    find . -maxdepth 1
    echo "=== find -maxdepth 1 -type f output ==="
    find . -maxdepth 1 -type f
    echo "=== find -maxdepth 1 -type l output (symlinks) ==="
    find . -maxdepth 1 -type l

    shopt -s nullglob

    echo "=== Running R1 mv loop ==="
    for file in *R1_001.fastq.gz; do
        new_name=\$(echo "\$file" | sed 's/_R1_001\\.fastq\\.gz/_1.fastq.gz/')
        echo "mv \$file -> \$new_name"
        mv "\$file" "\$new_name"
    done
    for file in *R2_001.fastq.gz; do
        new_name=\$(echo "\$file" | sed 's/_R2_001\\.fastq\\.gz/_2.fastq.gz/')
        echo "mv \$file -> \$new_name"
        mv "\$file" "\$new_name"
    done

    mkdir renamed

    echo "=== Files after mv ==="
    ls -la

    echo "=== Running Python renamer ==="
    find . -maxdepth 1 -type f | while read f; do
        echo "Processing: \$f"
        python3 ${scripts}/sculpt_name/sculpt_name_v3.py "\$f"
    done

    echo "=== renamed/ contents ==="
    ls -la renamed/ || echo "(renamed/ is empty or missing)"
    """
}

workflow {
    scripts_ch = Channel.value(file("${projectDir}/scripts"))

    CREATE_TEST_INPUTS()

    SCULPT(CREATE_TEST_INPUTS.out, scripts_ch)
}
