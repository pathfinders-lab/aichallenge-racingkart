#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

MPC_DIR="$(cd "./aichallenge/workspace/src/aichallenge_submit/multi_purpose_mpc_ros_custom" && pwd)"
MPC_PKG_CONFIG_DIR="$MPC_DIR/multi_purpose_mpc_ros_custom/config"
GIT_VERSION_PATH="$MPC_PKG_CONFIG_DIR/GIT_VERSION"
RUN_ID_PATH="$MPC_PKG_CONFIG_DIR/MLFLOW_RUN_ID"

trap 'rm -f "$GIT_VERSION_PATH" "$RUN_ID_PATH"' EXIT

# Pre-clean any stale stamp files from a previously interrupted run before
# register_submission.py's dirty check runs, to prevent false-dirty results
rm -f "$GIT_VERSION_PATH" "$RUN_ID_PATH"

echo "Registering submission in MLflow..." >&2
REGISTER_OUTPUT="$(cd racingkart-analysis && make register-submission MPC_REPO="$MPC_DIR")"
VERSION="$(printf '%s\n' "$REGISTER_OUTPUT" | sed -n 's/^VERSION=//p')"
RUN_ID="$(printf '%s\n' "$REGISTER_OUTPUT" | sed -n 's/^RUN_ID=//p')"

if [ -z "$VERSION" ] || [ -z "$RUN_ID" ]; then
    echo "ERROR: register-submission did not return VERSION/RUN_ID; aborting." >&2
    exit 1
fi

case "$VERSION" in
*-dirty)
    echo "WARNING: multi_purpose_mpc_ros_custom has uncommitted changes." >&2
    echo "         Full MPC parameters will be logged in autoware.log (no redaction)." >&2
    echo "         Commit first if you want parameter details kept out of the log." >&2
    ;;
esac

echo "$VERSION" >"$GIT_VERSION_PATH"
echo "$RUN_ID" >"$RUN_ID_PATH"

tar zcvf submit/aichallenge_submit.tar.gz -C ./aichallenge/workspace/src aichallenge_submit
