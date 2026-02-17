#!/usr/bin/env python3

# Nextflow interpolates these variables at runtime
sample_id = "$sample_id"
sequence = "$sequence"

# Write results to output file
output_file = f"{sample_id}_result.txt"
with open(output_file, 'w') as f:
    f.write(f"Sample: {sample_id}\n")
    f.write(f"Sequence: {sequence}\n")
    f.write(f"Length: {len(sequence)} bp\n")

print(f"Processed {sample_id}")
