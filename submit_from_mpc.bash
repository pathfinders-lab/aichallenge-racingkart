#!/bin/bash
# One-command official submission: build the tarball from a given mpc commit
# in an isolated git worktree, then upload it to the aichallenge board.
#
# Usage:
#   ./submit_from_mpc.bash [MPC_COMMIT] [-p "purpose"] [--dry-run] [--yes]
#
#   MPC_COMMIT  mpc (multi_purpose_mpc_ros_custom) commit/branch to package.
#               Defaults to origin/main.
#   -p TEXT     Short purpose appended to the board comment (max 15 chars).
#   --dry-run   Stop right before the actual upload (gates + summary only).
#   --yes       Skip the upload confirmation prompt (non-interactive use).
#
# Shared checkouts are never touched: the tarball is built from origin/develop
# in a throwaway worktree under .claude/worktrees/ (unique per run, removed on
# exit even on failure), with only the mpc submodule moved to MPC_COMMIT.
# Credentials: AIC_BOARD_USERNAME/PASSWORD from racingkart-analysis/.env
# (gitignored there — NEVER the parent .env, which is git-tracked), from the
# environment, or from ~/.aic_board_creds.
# Submitting consumes one of the team's 10 daily eval slots.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ANALYSIS_DIR="${ANALYSIS_DIR:-$SCRIPT_DIR/racingkart-analysis}"
MPC_PATH="aichallenge/workspace/src/aichallenge_submit/multi_purpose_mpc_ros_custom"

MPC_COMMIT="origin/main"
PURPOSE=""
DRY_RUN=0
YES=()
while [ $# -gt 0 ]; do
    case "$1" in
    -p | --purpose)
        PURPOSE="$2"
        shift 2
        ;;
    --dry-run)
        DRY_RUN=1
        shift
        ;;
    --yes)
        YES=(--yes)
        shift
        ;;
    -h | --help)
        sed -n '2,19p' "$0" | sed 's/^# \{0,1\}//'
        exit 0
        ;;
    *)
        MPC_COMMIT="$1"
        shift
        ;;
    esac
done

# Keep board comments short: "<id> mpc@<sha>" already traces the submission,
# so the free-form purpose may add at most 15 characters.
if [ "${#PURPOSE}" -gt 15 ]; then
    echo "ERROR: purpose is ${#PURPOSE} chars (max 15): ${PURPOSE}" >&2
    exit 1
fi

if [ ! -f "$ANALYSIS_DIR/Makefile" ]; then
    echo "ERROR: racingkart-analysis not found at $ANALYSIS_DIR" >&2
    echo "       (run 'git submodule update --init racingkart-analysis' first)" >&2
    exit 1
fi
# Load credentials: racingkart-analysis/.env first (also carries the MLflow
# settings), then ~/.aic_board_creds as an override if present.
if [ -f "$ANALYSIS_DIR/.env" ]; then
    set -a
    # shellcheck disable=SC1091
    . "$ANALYSIS_DIR/.env"
    set +a
fi
if [ -f "$HOME/.aic_board_creds" ]; then
    set -a
    # shellcheck disable=SC1091
    . "$HOME/.aic_board_creds"
    set +a
fi

cd "$SCRIPT_DIR"
git fetch -q origin

# Unique worktree per run so concurrent sessions can never collide.
WT="$SCRIPT_DIR/.claude/worktrees/submit-$(date +%Y%m%d%H%M%S)-$$"
cleanup() { git -C "$SCRIPT_DIR" worktree remove --force "$WT" 2>/dev/null || true; }
trap cleanup EXIT
git worktree add -q --detach "$WT" origin/develop
git -C "$WT" submodule update --init "$MPC_PATH" >/dev/null
MPC_DIR="$WT/$MPC_PATH"
git -C "$MPC_DIR" fetch -q origin
git -C "$MPC_DIR" checkout -q "$MPC_COMMIT"
MPC_SHA="$(git -C "$MPC_DIR" rev-parse --short HEAD)"
echo "Packaging mpc @ ${MPC_SHA} ($(git -C "$MPC_DIR" log -1 --format=%s))"

# Pre-register the MLflow run and stamp the config (same contract as
# create_submit_file.bash, but against the isolated worktree, always clean).
REGISTER_OUTPUT="$(cd "$ANALYSIS_DIR" && make -s register-submission MPC_REPO="$MPC_DIR")"
VERSION="$(printf '%s\n' "$REGISTER_OUTPUT" | sed -n 's/^VERSION=//p')"
RUN_ID="$(printf '%s\n' "$REGISTER_OUTPUT" | sed -n 's/^RUN_ID=//p')"
if [ -z "$VERSION" ] || [ -z "$RUN_ID" ]; then
    echo "ERROR: register-submission did not return VERSION/RUN_ID; aborting." >&2
    exit 1
fi
echo "MLflow run pre-registered: ${RUN_ID}"

CFG="$MPC_DIR/multi_purpose_mpc_ros_custom/config"
echo "$VERSION" >"$CFG/GIT_VERSION"
echo "$RUN_ID" >"$CFG/MLFLOW_RUN_ID"
mkdir -p "$SCRIPT_DIR/submit"
TAR="$SCRIPT_DIR/submit/aichallenge_submit.tar.gz"
tar zcf "$TAR" -C "$WT/aichallenge/workspace/src" aichallenge_submit
SHA256="$(sha256sum "$TAR" | cut -d' ' -f1)"

# Board comment: per-day sequence id, same ledger as submit/comment.bash.
LOG="$SCRIPT_DIR/submit/.submission_log"
touch "$LOG"
TODAY="$(date +%Y-%m-%d)"
N="$(grep -c "^${TODAY}" "$LOG" || true)"
LETTERS="abcdefghijklmnopqrstuvwxyz"
ID="${TODAY}${LETTERS:N:1}"
COMMENT="${ID} mpc@${MPC_SHA}${PURPOSE:+ ${PURPOSE}}"
echo "comment: ${COMMENT}"

ARM=(env AIC_BOARD_SUBMIT=1)
if [ "$DRY_RUN" -eq 1 ]; then
    ARM=(env)
fi
RC=0
(cd "$ANALYSIS_DIR" && "${ARM[@]}" PYTHONPATH= uv run python scripts/upload_submission.py \
    --file "$TAR" --comment "$COMMENT" ${YES[@]+"${YES[@]}"}) || RC=$?

if [ "$DRY_RUN" -eq 1 ]; then
    if [ "$RC" -eq 4 ]; then
        echo "Dry run OK: gates passed, nothing was submitted."
        exit 0
    fi
    echo "Dry run ended with rc=${RC} (expected 4)." >&2
    exit "$RC"
fi
if [ "$RC" -ne 0 ]; then
    echo "Upload did not complete (rc=${RC})." >&2
    echo "Do NOT immediately re-run: check the board first (a re-run is a NEW submission)." >&2
    exit "$RC"
fi
echo "${TODAY} ${ID} main ${SHA256} ${COMMENT}" >>"$LOG"
echo "Submitted ${ID}. After the eval finishes, fetch the results with:"
echo "  cd racingkart-analysis"
echo "  make sync-board"
