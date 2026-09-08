#!/bin/bash

# Returns a read group (RG) string
# For ids following: PREFIX_SAMPLE_FLOWCELL_SAMPLENUM_LANE
# Update to your files' naming convention if needed

file_id="$1"
platform="$2"

IFS='_' read -r prefix sample flowcell sample_num lane <<< "$file_id"

SAMPLE=${prefix}_${sample}_${flowcell}
FLOWCELL=${flowcell}
LANE=${lane}

RG="@RG\tID:${FLOWCELL}.${LANE}\tSM:${SAMPLE}\tLB:${SAMPLE}\tPL:ILLUMINA\tPU:${FLOWCELL}.${LANE}"
echo "$RG"

# dummy values for testing
# RG="@RG\tID:DUMMY_ID\tSM:DUMMY_SM\tPL:ILLUMINA"
# echo "$RG"