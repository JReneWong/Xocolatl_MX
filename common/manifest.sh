#!/usr/bin/env bash
# Shared helper, sourced by every pipeline/00N_Module/bin/run_*.sh — never
# run directly. Wraps one actual command, times it, and writes
# results/manifest_<timestamp>.yaml capturing what ran: the exact command,
# container + its digest, resources, git commit of the scripts, inputs
# consumed, outputs produced, and the exit code — so any run can be
# reproduced or audited later without guessing.
#
# Deliberately does NOT checksum input files: our fastqs/BAMs are tens of
# GB, and sha256-ing them on every run would make the wrapper itself the
# bottleneck. We record the resolved symlink target instead, which is
# enough to know exactly which file was used.

# Usage: run_and_log MODULE_DIR CONTAINER_SIF CPUS MEM -- <command...>
run_and_log() {
    local module_dir="$1"; shift
    local container_sif="$1"; shift
    local cpus="$1"; shift
    local mem="$1"; shift
    [ "$1" = "--" ] && shift
    local cmd=("$@")

    local results_dir="$module_dir/results"
    mkdir -p "$results_dir"

    local ts
    ts="$(date -u +'%Y%m%dT%H%M%SZ')"
    local manifest="$results_dir/manifest_${ts}.yaml"

    local container_sha=""
    if [ -f "$container_sif" ]; then
        container_sha="$(sha256sum "$container_sif" | cut -d' ' -f1)"
    fi

    local git_commit=""
    git_commit="$(git -C "$module_dir" rev-parse HEAD 2>/dev/null || echo "unknown")"

    local marker
    marker="$(mktemp)"

    local start_epoch end_epoch exit_code
    start_epoch=$(date -u +%s)
    set +e
    "${cmd[@]}"
    exit_code=$?
    set -e
    end_epoch=$(date -u +%s)

    {
        echo "module: $(basename "$module_dir")"
        echo "timestamp_utc: $ts"
        echo "duration_seconds: $((end_epoch - start_epoch))"
        echo "command: >"
        printf '  %q' "${cmd[@]}"
        echo
        echo "container: $container_sif"
        echo "container_sha256: $container_sha"
        echo "resources:"
        echo "  cpus: $cpus"
        echo "  mem: $mem"
        echo "git_commit: $git_commit"
        echo "exit_code: $exit_code"
        echo "inputs:"
        find "$module_dir/data" -maxdepth 1 \( -type f -o -type l \) 2>/dev/null | sort | while read -r f; do
            resolved="$(readlink -f "$f" 2>/dev/null || echo "$f")"
            echo "  - path: $f"
            echo "    resolved: $resolved"
        done
        echo "outputs:"
        find "$results_dir" -maxdepth 1 -type f ! -name 'manifest_*' -newer "$marker" 2>/dev/null | sort | while read -r f; do
            echo "  - $f"
        done
    } > "$manifest"

    rm -f "$marker"
    ln -sf "$(basename "$manifest")" "$results_dir/manifest_latest.yaml"
    echo "Manifest written: $manifest"
    return $exit_code
}
