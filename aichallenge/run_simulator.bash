#!/bin/bash

SCRIPT_DIR="$(dirname "$0")/simulator_scripts"
mode="${1:-${SIM_MODE:-simulator}}"
[ $# -gt 0 ] && shift

# dev2 / gate2 等は dev.sh / gate.sh に番号を渡すエイリアス
[[ ${mode} =~ ^(dev|gate)([0-9]+)$ ]] && set -- "${BASH_REMATCH[2]}" "$@" && mode="${BASH_REMATCH[1]}"

# simulator_scripts 内のスクリプトを呼び出す
script="${SCRIPT_DIR}/${mode}.sh"
if [[ ! -f ${script} ]]; then
    echo "[ERROR] unknown mode '${mode}' (supported: $(basename -s .sh "${SCRIPT_DIR}"/*.sh | xargs) dev<N> gate<N>)" >&2
    exit 1
fi

log_dir="${LOG_DIR:-/output}"
mkdir -p "${log_dir}"
exec >"${log_dir}/awsim.log" 2>&1

# Fingerprint the AWSIM build that is about to run so the analysis side can
# tag MLflow runs with the exact simulator version (the build carries no
# version string). Best-effort: failure must never block the launch.
gg_file="/aichallenge/simulator/AWSIM/AWSIM_Data/globalgamemanagers"
if [[ -f ${gg_file} ]] && command -v md5sum >/dev/null 2>&1; then
    gg_md5=$(md5sum "${gg_file}" | cut -d' ' -f1) &&
        printf '{"awsim_dir": "/aichallenge/simulator/AWSIM", "globalgamemanagers_md5": "%s"}\n' \
            "${gg_md5}" >"${log_dir}/awsim_fingerprint.json"
fi

echo "[INFO] Starting AWSIM: ${mode}.sh $*"
exec bash "${script}" "$@"
