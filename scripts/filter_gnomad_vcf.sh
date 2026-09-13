#!/bin/bash

input_dir="$1" # dir with gnomad .vcf.bgz files
output_dir="${2:-.}"

for input_file in "$input_dir"/*.vcf.bgz; do
    echo "Processing $input_file"
    [[ -e "$input_file" ]] || continue
    filename=$(basename "$input_file" .vcf.bgz)
    output_file="$output_dir/${filename}.lof_missense.vcf.bgz"

    bcftools annotate -x "^INFO/AF,INFO/vep" "$input_file" \
        | bcftools +split-vep -a vep -c Consequence \
        | bcftools annotate -x 'INFO/vep' \
        | bcftools view -i "INFO/Consequence[*] ~ \"splice_acceptor_variant\" || \
        INFO/Consequence[*] ~ \"splice_donor_variant\" || \
        INFO/Consequence[*] ~ \"stop_gained\" || \
        INFO/Consequence[*] ~ \"frameshift_variant\" || \
        INFO/Consequence[*] ~ \"transcript_ablation\" || \
        INFO/Consequence[*] ~ \"missense_variant\" || \
        INFO/Consequence[*] ~ \"inframe_insertion\" || \
        INFO/Consequence[*] ~ \"inframe_deletion\" || \
        INFO/Consequence[*] ~ \"stop_lost\" || \
        INFO/Consequence[*] ~ \"start_lost\"" \
        | bcftools annotate -x 'INFO/Consequence' \
        -o "$output_file"
    echo "Wrote to $output_file"
done

# files=()
# for chr in {1..22} X Y; do
#   files+=( "$output_dir"/*.chr$chr.lof_missense.vcf.bgz )
# done

# bcftools concatenate --write-index="tbi" "${files[@]}" -o "$output_dir/concatenated.lof_missense.vcf.bgz"