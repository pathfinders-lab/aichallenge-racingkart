#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

MPC_DIR="./aichallenge/workspace/src/aichallenge_submit/multi_purpose_mpc_ros_custom"
GIT_VERSION_PATH="$MPC_DIR/multi_purpose_mpc_ros_custom/config/GIT_VERSION"

trap 'rm -f "$GIT_VERSION_PATH"' EXIT

MPC_HASH="$(git -C "$MPC_DIR" rev-parse --short HEAD)"
if [ -n "$(git -C "$MPC_DIR" status --porcelain)" ]; then
    echo "WARNING: multi_purpose_mpc_ros_custom has uncommitted changes." >&2
    echo "         Full MPC parameters will be logged in autoware.log (no redaction)." >&2
    echo "         Commit first if you want parameter details kept out of the log." >&2
    echo "${MPC_HASH}-dirty" >"$GIT_VERSION_PATH"
else
    echo "${MPC_HASH}" >"$GIT_VERSION_PATH"
fi

tar zcvf submit/aichallenge_submit.tar.gz -C ./aichallenge/workspace/src aichallenge_submit
