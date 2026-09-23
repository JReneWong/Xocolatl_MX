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

# Usage: CONTAINER="$(resolve_container "$PROJECT_ROOT")"
#    or: CONTAINER="$(resolve_container "$PROJECT_ROOT" "shapeit")"
# The .sif is arch-specific (container/<base_name>_<arch>.sif) — the team
# builds on both Apple Silicon Macs (via the Lima VM, arm64) and x86_64
# Linux, and a .sif built for one arch cannot run on the other
# ("the image's architecture ... could not run on the host's"). base_name
# defaults to "hackathon" (the main pipeline container) so every existing
# call site keeps working unchanged; pass a second arg to resolve a
# different container built the same arch-specific way (e.g. "shapeit").
resolve_container() {
    local project_root="$1"
    local base_name="${2:-hackathon}"
    case "$(uname -m)" in
        x86_64)  echo "$project_root/container/${base_name}_amd64.sif" ;;
        aarch64) echo "$project_root/container/${base_name}_arm64.sif" ;;
        *) echo "Unsupported architecture: $(uname -m)" >&2; return 1 ;;
    esac
}

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

    local git_commit="unknown"
    if git -C "$module_dir" rev-parse --verify HEAD >/dev/null 2>&1; then
        git_commit="$(git -C "$module_dir" rev-parse HEAD)"
    fi

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
        local input_dir="${MANIFEST_INPUT_DIR:-$module_dir/data}"
        find "$input_dir" -maxdepth 1 \( -type f -o -type l \) 2>/dev/null | sort | while read -r f; do
            # Only trust readlink -f on an actual symlink. On exFAT mounted
            # natively on Linux, a macOS-created symlink shows up as a
            # plain file (Apple's exFAT symlink emulation isn't portable),
            # so readlink -f would otherwise silently "resolve" it to
            # itself and look correct when it isn't.
            if [ -L "$f" ]; then
                resolved="$(readlink -f "$f" 2>/dev/null || echo "$f")"
            else
                resolved="$f"
            fi
            echo "  - path: $f"
            echo "    resolved: $resolved"
        done
        echo "outputs:"
        find "$results_dir" -maxdepth 1 -type f ! -name 'manifest_*' -newer "$marker" 2>/dev/null | sort | while read -r f; do
            echo "  - $f"
        done
    } > "$manifest"

    rm -f "$marker"
    # A real symlink where the filesystem supports it (e.g. this repo
    # shared into the Lima VM on macOS); exFAT mounted natively on Linux
    # can't create symlinks at all ("Operation not permitted"), so fall
    # back to a plain copy there — same end result for readers, just not
    # a live link.
    if ! ln -sf "$(basename "$manifest")" "$results_dir/manifest_latest.yaml" 2>/dev/null; then
        cp -f "$manifest" "$results_dir/manifest_latest.yaml"
    fi
    echo "Manifest written: $manifest"
    return $exit_code
}
