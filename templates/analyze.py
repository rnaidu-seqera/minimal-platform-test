#!/usr/bin/env python3

"""
Simple analysis script used as a Nextflow template.

This demonstrates the template directive. Nextflow will interpolate
variables prefixed with $ when the pipeline runs.
"""

import sys
from datetime import datetime

# These variables are interpolated by Nextflow at runtime
sample_id = "$sample_id"
sequence = "$sequence"

def analyze_sequence(seq_id, seq_data):
    """Simple sequence analysis"""
    length = len(seq_data)
    gc_count = seq_data.count('G') + seq_data.count('C')
    gc_percent = (gc_count / length * 100) if length > 0 else 0

    return {
        'id': seq_id,
        'length': length,
        'gc_content': gc_percent,
        'sequence': seq_data
    }

def main():
    print(f"Starting analysis at {datetime.now()}", file=sys.stderr)
    print(f"Analyzing sample: {sample_id}", file=sys.stderr)

    # Perform analysis
    result = analyze_sequence(sample_id, sequence)

    # Write results to output file
    output_file = f"{sample_id}_result.txt"
    with open(output_file, 'w') as f:
        f.write(f"Sample ID: {result['id']}\n")
        f.write(f"Sequence: {result['sequence']}\n")
        f.write(f"Length: {result['length']} bp\n")
        f.write(f"GC Content: {result['gc_content']:.2f}%\n")

    print(f"Analysis complete. Results written to {output_file}", file=sys.stderr)

if __name__ == "__main__":
    main()
