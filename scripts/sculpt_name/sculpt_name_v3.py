import sys
import os
import re


def validate_name(name):
    name = os.path.basename(name)
    name, _ = os.path.splitext(name)
    print(name)

    pattern = re.compile(r'^(PH\d{4}|[A-Z]\d{3}|(E?RS)(_[A-Za-z0-9]+|\d+))(?:_LEN.*)?$')
    if not pattern.match(name):
        return False
    else:
        return True

def fill_space_with_zeroes(input_string):
    if "external" in input_string or re.match(r'^(E?RS)(_[A-Za-z0-9]+|\d+)', input_string):
        return input_string

    num = 4 if "PH" in input_string else 3

    pattern = re.compile(r'([a-zA-Z]+)(\d+)')

    def normalize(match):
        prefix, digits = match.groups()
        normalized_digits = str(int(digits)).zfill(num)
        return f"{prefix}{normalized_digits}"

    return re.sub(pattern, normalize, input_string)


def sculptor(name):
    orig = name
    parts = 0
    include_keywords = ["fasta", "fastq"]
    if any(keyword in name for keyword in include_keywords):
        if "phg" in name:
            match = re.search(r'phg(.*?)phg', name)
            result = match.group(1)
            result = fill_space_with_zeroes(result)
            if validate_name(result) == True:
                for extension in [".fasta", "1.fastq.gz", "2.fastq.gz"]:
                    if extension in name and "fasta" in extension:
                        os.rename(orig, "renamed/" + result + extension)
                    if extension in name and "fastq" in extension:
                        os.rename(orig, "renamed/PHS_" + result + "_PHS_" + extension)
                return()
            else:
                print(f"Skipping invalid name: {result}")
        if "meta" in name:
            match = re.search(r'meta(.*?)meta', name)
            result = match.group(1)
            if ".fasta" in name or ".fna" in name:
                os.rename(orig, "renamed/" + result + ".fasta")
            elif "_R1_" in name or "_1.fastq" in name:
                ext = ".fastq.gz" if name.endswith(".gz") else ".fastq"
                os.rename(orig, "renamed/" + result + "_1" + ext)
            elif "_R2_" in name or "_2.fastq" in name:
                ext = ".fastq.gz" if name.endswith(".gz") else ".fastq"
                os.rename(orig, "renamed/" + result + "_2" + ext)
            else:
                base_ext = os.path.splitext(orig)[1]
                os.rename(orig, "renamed/" + result + base_ext)
            return()
        if "fastq.gz" in name:
            parts = name.split("_")
            parts[1] = fill_space_with_zeroes(parts[1])
            if validate_name(parts[1]) == True:
                parts = ("_").join(parts)
                print("Renaming " + orig + " to " + parts)
                os.rename(orig, "renamed/" + parts)
            else:
                print(f"Skipping invalid name: {parts[1]}")

        else:
            print("Renaming " + orig + " to " + fill_space_with_zeroes(name))
            if validate_name(fill_space_with_zeroes(name)) == True:
                os.rename(orig, "renamed/" + fill_space_with_zeroes(name))
            else:
                print(f"Skipping invalid name: {fill_space_with_zeroes(name)}")

sculptor(sys.argv[1])
