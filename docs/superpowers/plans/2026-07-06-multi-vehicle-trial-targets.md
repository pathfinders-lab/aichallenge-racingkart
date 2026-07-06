# Multi-Vehicle Trial Targets (trial2/trial3) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add `make trial2`/`trial2-quick`/`trial3`/`trial3-quick` — headless, bounded-duration, auto-torn-down multi-vehicle simulation targets with the same one-command ease as the existing single-vehicle `make trial`/`trial-quick`.

**Architecture:** Four new `simulator_scripts/*.sh` files (copied from the existing 3-vehicle `parallel.sh` race preset, with collisions enabled, count-mode start, and `-headless`, mirroring `trial.sh`'s 7-lap/`trial-quick.sh`'s 3-lap cadence) plus four new `Makefile` targets that combine `trial`/`trial-quick`'s "launch → wait → down" skeleton with `dev2/dev3/dev4`'s "loop over N per-domain `docker compose -p` autoware instances" skeleton. No `racingkart-analysis` integration — this only produces raw per-vehicle rosbags (`output/<timestamp>/d1`, `d2`, `d3`); full multi-vehicle metrics extraction is separate, later Phase 2 evaluation-framework work.

**Tech Stack:** Bash, GNU Make, Docker Compose, AWSIM CLI.

**Spec:** `docs/superpowers/specs/2026-07-06-multi-vehicle-trial-design.md`

## Global Constraints

- Every new `simulator_scripts/*.sh` file is self-contained (no shared config file) — this repo's `simulator_scripts/README.md` explicitly documents "1 mode = 1 file, deliberately not DRY'd" as the convention; do not centralize settings across the 4 new files.
- `--collisions on`, `--start-mode count --start-count-seconds 10`, and a trailing `-headless` flag are required in all 4 new scripts (deviating from `parallel.sh`'s `--collisions off`/`--start-mode sync`, which is fine unattended in a GUI dev session but not for a one-shot headless target).
- Full-length scripts (`trial2.sh`, `trial3.sh`): `--laps 7 --timeout 600`, shell-level hard cap `timeout 800` (matches `trial.sh` exactly: 10s countdown + 600s AWSIM timeout + ~190s init/buffer).
- Quick scripts (`trial2-quick.sh`, `trial3-quick.sh`): `--laps 3 --timeout 200`, shell-level hard cap `timeout 400` (matches `trial-quick.sh` exactly).
- `handicap on`, `ranking on`, `wall-recovery on`, `--boosts 2`, `--npcs 0` are unchanged from `parallel.sh` in all 4 files — only the four items above and `--vehicles N`/`--laps`/`--timeout` change.
- No `racingkart-analysis analyze`/MLflow call in any new Makefile target — success output is a plain message listing the rosbag output directories.
- New Makefile targets must reuse the existing `simulator`, `down` targets and `docker compose wait simulator` exit-code convention (`0` or `124` = success, anything else = crash) exactly as `trial`/`trial-quick` do.

---

### Task 1: AWSIM launch scripts + README table

**Files:**
- Create: `aichallenge/simulator_scripts/trial2.sh`
- Create: `aichallenge/simulator_scripts/trial2-quick.sh`
- Create: `aichallenge/simulator_scripts/trial3.sh`
- Create: `aichallenge/simulator_scripts/trial3-quick.sh`
- Modify: `aichallenge/simulator_scripts/README.md` (mode table)

**Interfaces:**
- Produces: four executable scripts, each invoked as `bash aichallenge/simulator_scripts/<name>.sh` with no arguments (matching `trial.sh`/`trial-quick.sh`/`parallel.sh`'s calling convention — `run_simulator.bash` execs them directly since none of these names match the `^(dev|gate)([0-9]+)$` alias regex in `aichallenge/run_simulator.bash:7`, so no special-casing is needed there).

- [ ] **Step 1: Create `trial2.sh`**

```bash
#!/bin/bash

AWSIM_DIRECTORY=/aichallenge/simulator/AWSIM
export ROS_DOMAIN_ID=0

# 2-vehicle version of trial.sh: 7-lap run (6 measured laps + 1, so "Lap 6
# completed" logs before Finish fires -- same reasoning as trial.sh/trial-quick.sh).
# Race preset (parallel.sh) with collisions on and count-mode start so
# `make trial2` completes unattended, unlike parallel.sh's sync-start
# (which waits for a manual /admin/awsim/start).
# Shell-level hard cap: countdown (10 s) + AWSIM --timeout (600 s) + init/buffer (~190 s) = 800 s.
exec timeout 800 "$AWSIM_DIRECTORY/AWSIM.x86_64" \
    --start-mode count \
    --start-count-seconds 10 \
    --vehicles 2 \
    --npcs 0 \
    --boosts 2 \
    --laps 7 \
    --timeout 600 \
    --steer-source ackermann \
    --sound off \
    --collisions on \
    --handicap on \
    --wall-recovery on \
    --ranking on \
    --camera off \
    --lidar off \
    -headless

# Cameraを使う場合 : --camera cpu or gpu
# LiDARを使う場合 : --lidar cpu or gpu
```

- [ ] **Step 2: Create `trial2-quick.sh`**

```bash
#!/bin/bash

AWSIM_DIRECTORY=/aichallenge/simulator/AWSIM
export ROS_DOMAIN_ID=0

# 2-vehicle quick-exploration version of trial-quick.sh: 3-lap run (2 measured
# laps + 1, same reasoning as trial.sh/trial-quick.sh). Race preset
# (parallel.sh) with collisions on and count-mode start so `make
# trial2-quick` completes unattended, unlike parallel.sh's sync-start.
# Shell-level hard cap: countdown (10 s) + AWSIM --timeout (200 s) + init/buffer (~190 s) = 400 s.
exec timeout 400 "$AWSIM_DIRECTORY/AWSIM.x86_64" \
    --start-mode count \
    --start-count-seconds 10 \
    --vehicles 2 \
    --npcs 0 \
    --boosts 2 \
    --laps 3 \
    --timeout 200 \
    --steer-source ackermann \
    --sound off \
    --collisions on \
    --handicap on \
    --wall-recovery on \
    --ranking on \
    --camera off \
    --lidar off \
    -headless

# Cameraを使う場合 : --camera cpu or gpu
# LiDARを使う場合 : --lidar cpu or gpu
```

- [ ] **Step 3: Create `trial3.sh`**

```bash
#!/bin/bash

AWSIM_DIRECTORY=/aichallenge/simulator/AWSIM
export ROS_DOMAIN_ID=0

# 3-vehicle version of trial.sh (parallel.sh's own vehicle count): 7-lap run
# (6 measured laps + 1, so "Lap 6 completed" logs before Finish fires -- same
# reasoning as trial.sh/trial-quick.sh). Race preset (parallel.sh) with
# collisions on and count-mode start so `make trial3` completes unattended,
# unlike parallel.sh's sync-start (which waits for a manual /admin/awsim/start).
# Shell-level hard cap: countdown (10 s) + AWSIM --timeout (600 s) + init/buffer (~190 s) = 800 s.
exec timeout 800 "$AWSIM_DIRECTORY/AWSIM.x86_64" \
    --start-mode count \
    --start-count-seconds 10 \
    --vehicles 3 \
    --npcs 0 \
    --boosts 2 \
    --laps 7 \
    --timeout 600 \
    --steer-source ackermann \
    --sound off \
    --collisions on \
    --handicap on \
    --wall-recovery on \
    --ranking on \
    --camera off \
    --lidar off \
    -headless

# Cameraを使う場合 : --camera cpu or gpu
# LiDARを使う場合 : --lidar cpu or gpu
```

- [ ] **Step 4: Create `trial3-quick.sh`**

```bash
#!/bin/bash

AWSIM_DIRECTORY=/aichallenge/simulator/AWSIM
export ROS_DOMAIN_ID=0

# 3-vehicle quick-exploration version of trial-quick.sh: 3-lap run (2 measured
# laps + 1, same reasoning as trial.sh/trial-quick.sh). Race preset
# (parallel.sh) with collisions on and count-mode start so `make
# trial3-quick` completes unattended, unlike parallel.sh's sync-start.
# Shell-level hard cap: countdown (10 s) + AWSIM --timeout (200 s) + init/buffer (~190 s) = 400 s.
exec timeout 400 "$AWSIM_DIRECTORY/AWSIM.x86_64" \
    --start-mode count \
    --start-count-seconds 10 \
    --vehicles 3 \
    --npcs 0 \
    --boosts 2 \
    --laps 3 \
    --timeout 200 \
    --steer-source ackermann \
    --sound off \
    --collisions on \
    --handicap on \
    --wall-recovery on \
    --ranking on \
    --camera off \
    --lidar off \
    -headless

# Cameraを使う場合 : --camera cpu or gpu
# LiDARを使う場合 : --lidar cpu or gpu
```

- [ ] **Step 5: Verify shell syntax on all 4 scripts**

Run: `bash -n aichallenge/simulator_scripts/trial2.sh aichallenge/simulator_scripts/trial2-quick.sh aichallenge/simulator_scripts/trial3.sh aichallenge/simulator_scripts/trial3-quick.sh`
Expected: no output, exit code 0 (bash `-n` only parses, doesn't execute — `AWSIM_DIRECTORY` need not exist for this check)

- [ ] **Step 6: Diff each new script against `parallel.sh` to confirm only the intended fields changed**

Run: `diff aichallenge/simulator_scripts/parallel.sh aichallenge/simulator_scripts/trial3.sh`
Expected diff (only these lines differ — comment block, `--laps`, `--timeout`, `--collisions`, `--start-mode`/`--start-count-seconds`, the trailing `-screen-*`/`-window-mode` lines removed, and `-headless` added):
```
< (parallel.sh's original top comment)
---
> (trial3.sh's new comment block)
...
<     --laps 6 \
<     --timeout 600.0 \
---
>     --laps 7 \
>     --timeout 600 \
...
<     --collisions off \
---
>     --collisions on \
...
<     --start-mode sync \
<     --start-count-seconds 5 \
---
>     --start-mode count \
>     --start-count-seconds 10 \
...
<     -screen-fullscreen 1 \
<     -screen-width 1920 \
<     -screen-height 1080 \
<     -screen-quality low \
<     -window-mode borderless # Unity default arg
---
>     -headless
```
Run the equivalent `diff` for `trial2.sh` (expect the same shape of diff, plus `--vehicles 3` → `--vehicles 2`), and for the two `-quick` variants (expect the same diff shape as their non-quick counterpart, plus `--laps 7`→`3` and `--timeout 600`→`200`, and `exec timeout 800`→`exec timeout 400`). If any diff shows an unexpected change (e.g. `--handicap`, `--ranking`, `--boosts`, `--npcs`, `--wall-recovery` differing from `parallel.sh`), fix the new script — those must stay identical to `parallel.sh`.

- [ ] **Step 7: Update `aichallenge/simulator_scripts/README.md`'s mode table**

In the `## モード一覧` table, after the `parallel.sh` row, insert four new rows:

```markdown
| `trial2.sh` | 開発計測（`make trial2`） | - | 2台 / **7 laps** / 600s / count開始 / handicap・wall-recovery・ranking on / collisions on |
| `trial2-quick.sh` | 開発探索（`make trial2-quick`） | - | 2台 / **3 laps** / 200s / count開始 / handicap・wall-recovery・ranking on / collisions on |
| `trial3.sh` | 開発計測（`make trial3`） | - | 3台 / **7 laps** / 600s / count開始 / handicap・wall-recovery・ranking on / collisions on |
| `trial3-quick.sh` | 開発探索（`make trial3-quick`） | - | 3台 / **3 laps** / 200s / count開始 / handicap・wall-recovery・ranking on / collisions on |
```

Directly below the existing "`trial-quick.sh` が3 lapsを指定する理由" bullet, add:

```markdown
- `trial2.sh`/`trial3.sh`/`trial2-quick.sh`/`trial3-quick.sh` は `parallel.sh`（3台レースプリセット）をベースに、
  `--collisions on`・`--start-mode count`（`/admin/awsim/start` の手動送信不要）・`-headless` に変更し、
  周回数/timeoutは `trial.sh`/`trial-quick.sh` と揃えた（`parallel.sh` 本来の6 laps/600sではない）。
  racingkart-analysisのanalyze/MLflow連携は呼ばない（複数車両分の本格解析はPhase 2評価フレームワークで別途対応）。
```

- [ ] **Step 8: Commit**

```bash
git add aichallenge/simulator_scripts/trial2.sh aichallenge/simulator_scripts/trial2-quick.sh aichallenge/simulator_scripts/trial3.sh aichallenge/simulator_scripts/trial3-quick.sh aichallenge/simulator_scripts/README.md
git commit -m "feat: add trial2/trial2-quick/trial3/trial3-quick AWSIM launch scripts"
```

---

### Task 2: Makefile targets

**Files:**
- Modify: `Makefile`

**Interfaces:**
- Consumes: `simulator` target (`Makefile:57-59`, launches AWSIM via `SIM_MODE`), `down` target (`Makefile:160-162`, already loops `docker compose -p $$p down --remove-orphans` for `p` in `1 2 3 4` plus the default project — no change needed there), `TIMESTAMP`/`LOG_DIR` variables (`Makefile:18-19`, already computed once per `make` invocation).
- Produces: four new phony targets `trial2`, `trial2-quick`, `trial3`, `trial3-quick`, invocable as `make trial2` etc.

- [ ] **Step 1: Add the four targets to `.PHONY`**

In `Makefile`, change line 4-5 from:

```makefile
.PHONY: autoware-build autoware-vehicle autoware-simulator autoware-request-initialpose autoware-request-control  awsim-request-start awsim-request-reset autoware-driver-zenoh autoware-driver-zenoh-rosbag trial trial-quick \
	simulator dev dev2 dev3 dev4 driver zenoh download rviz2 down down_all ps autoware-attach autoware-bash eval optuna optuna-apply
```

to:

```makefile
.PHONY: autoware-build autoware-vehicle autoware-simulator autoware-request-initialpose autoware-request-control  awsim-request-start awsim-request-reset autoware-driver-zenoh autoware-driver-zenoh-rosbag trial trial-quick \
	simulator dev dev2 dev3 dev4 driver zenoh download rviz2 down down_all ps autoware-attach autoware-bash eval optuna optuna-apply \
	trial2 trial2-quick trial3 trial3-quick
```

- [ ] **Step 2: Add the four targets after the existing `dev2 dev3 dev4` block**

In `Makefile`, immediately after the `dev2 dev3 dev4` block (after the line `echo "To Stop: make down"` that follows it, before the `gate1 gate2 gate3` block), insert:

```makefile
# N-vehicle version of trial (7 laps; records /mpc/stats per vehicle; no analyze/MLflow —
# see docs/superpowers/specs/2026-07-06-multi-vehicle-trial-design.md for why).
# Blocks until AWSIM finishes, then runs make down automatically.
# Exit 0 = all laps done; exit 124 = AWSIM --timeout fired (normal); other = crash (stop).
trial2: SIM_MODE := trial2
trial2: simulator
	@echo "[trial2] AWSIM started (2 vehicles, 7 laps, ~10 min). Waiting for completion..."
	@for p in 1 2; do LOG_DIR=$(LOG_DIR) ROS_DOMAIN_ID=$$p docker compose -p $$p up -d autoware; done
	@docker compose wait simulator > /dev/null 2>&1; sim_exit=$$?; \
	if [ "$$sim_exit" -ne 0 ] && [ "$$sim_exit" -ne 124 ]; then \
	    echo "[trial2] ERROR: AWSIM crashed (exit $$sim_exit). Run 'make down' manually."; \
	    exit "$$sim_exit"; \
	fi
	@$(MAKE) --no-print-directory -s down 2>/dev/null
	@echo "[trial2] Done. rosbags saved at: output/$(TIMESTAMP)/d1, output/$(TIMESTAMP)/d2"

# N-vehicle version of trial-quick (3 laps; quick exploration).
# Blocks until AWSIM finishes, then runs make down automatically.
# Exit 0 = all laps done; exit 124 = AWSIM --timeout fired (normal); other = crash (stop).
trial2-quick: SIM_MODE := trial2-quick
trial2-quick: simulator
	@echo "[trial2-quick] AWSIM started (2 vehicles, 3 laps, ~5 min). Waiting for completion..."
	@for p in 1 2; do LOG_DIR=$(LOG_DIR) ROS_DOMAIN_ID=$$p docker compose -p $$p up -d autoware; done
	@docker compose wait simulator > /dev/null 2>&1; sim_exit=$$?; \
	if [ "$$sim_exit" -ne 0 ] && [ "$$sim_exit" -ne 124 ]; then \
	    echo "[trial2-quick] ERROR: AWSIM crashed (exit $$sim_exit). Run 'make down' manually."; \
	    exit "$$sim_exit"; \
	fi
	@$(MAKE) --no-print-directory -s down 2>/dev/null
	@echo "[trial2-quick] Done. rosbags saved at: output/$(TIMESTAMP)/d1, output/$(TIMESTAMP)/d2"

# N-vehicle version of trial (7 laps; records /mpc/stats per vehicle; no analyze/MLflow).
# Blocks until AWSIM finishes, then runs make down automatically.
# Exit 0 = all laps done; exit 124 = AWSIM --timeout fired (normal); other = crash (stop).
trial3: SIM_MODE := trial3
trial3: simulator
	@echo "[trial3] AWSIM started (3 vehicles, 7 laps, ~10 min). Waiting for completion..."
	@for p in 1 2 3; do LOG_DIR=$(LOG_DIR) ROS_DOMAIN_ID=$$p docker compose -p $$p up -d autoware; done
	@docker compose wait simulator > /dev/null 2>&1; sim_exit=$$?; \
	if [ "$$sim_exit" -ne 0 ] && [ "$$sim_exit" -ne 124 ]; then \
	    echo "[trial3] ERROR: AWSIM crashed (exit $$sim_exit). Run 'make down' manually."; \
	    exit "$$sim_exit"; \
	fi
	@$(MAKE) --no-print-directory -s down 2>/dev/null
	@echo "[trial3] Done. rosbags saved at: output/$(TIMESTAMP)/d1, output/$(TIMESTAMP)/d2, output/$(TIMESTAMP)/d3"

# N-vehicle version of trial-quick (3 laps; quick exploration).
# Blocks until AWSIM finishes, then runs make down automatically.
# Exit 0 = all laps done; exit 124 = AWSIM --timeout fired (normal); other = crash (stop).
trial3-quick: SIM_MODE := trial3-quick
trial3-quick: simulator
	@echo "[trial3-quick] AWSIM started (3 vehicles, 3 laps, ~5 min). Waiting for completion..."
	@for p in 1 2 3; do LOG_DIR=$(LOG_DIR) ROS_DOMAIN_ID=$$p docker compose -p $$p up -d autoware; done
	@docker compose wait simulator > /dev/null 2>&1; sim_exit=$$?; \
	if [ "$$sim_exit" -ne 0 ] && [ "$$sim_exit" -ne 124 ]; then \
	    echo "[trial3-quick] ERROR: AWSIM crashed (exit $$sim_exit). Run 'make down' manually."; \
	    exit "$$sim_exit"; \
	fi
	@$(MAKE) --no-print-directory -s down 2>/dev/null
	@echo "[trial3-quick] Done. rosbags saved at: output/$(TIMESTAMP)/d1, output/$(TIMESTAMP)/d2, output/$(TIMESTAMP)/d3"
```

- [ ] **Step 3: Verify with a dry run**

Run: `make -n trial2-quick`
Expected: prints the shell commands that would run — `docker compose up -d simulator` (with `SIM_MODE=trial2-quick` in its environment), then the `for p in 1 2; do ... docker compose -p $$p up -d autoware; done` loop, then the `docker compose wait simulator` block, then `$(MAKE) --no-print-directory -s down`, then the final `echo`. No `make: *** No rule to make target` or syntax errors.

Run the same for `trial2`, `trial3`, `trial3-quick` and confirm each prints its own vehicle count (`for p in 1 2 3`) and lap count in the first `echo` line.

- [ ] **Step 4: Commit**

```bash
git add Makefile
git commit -m "feat: add trial2/trial2-quick/trial3/trial3-quick Makefile targets"
```

---

### Task 3: Live verification run

**Files:** none (verification only)

This task requires actually running Docker + AWSIM, which cannot be dry-run. The user has already granted permission to execute this in this session, with a heads-up immediately beforehand since the environment may be shared with other sessions.

- [ ] **Step 1: Confirm no other simulator is currently running**

Run: `docker compose ps` and `docker ps --format '{{.Names}}'`
Expected: no containers named `*simulator*` or `*autoware*` already running. If any are found, stop and check with the user before proceeding (another session may be using them).

- [ ] **Step 2: Run the smallest/fastest new target**

Run: `make trial2-quick` (2 vehicles, 3 laps, ~5 minutes, blocks until done)
Expected: exits 0, prints `[trial2-quick] Done. rosbags saved at: output/<timestamp>/d1, output/<timestamp>/d2`. If it exits non-zero (crash) or hangs well past ~5 minutes, stop and investigate before proceeding to Step 3 — do not average by re-running blindly.

- [ ] **Step 3: Verify per-vehicle lap-completion logging**

Run: `grep -c "Lap 2 completed" output/<timestamp>/d1/autoware.log output/<timestamp>/d2/autoware.log` (substitute the actual timestamp printed in Step 2's output)
Expected: both files report at least 1 match. This is the concrete check for the spec's "未解決の懸念": if `ranking on` causes AWSIM's multi-vehicle Finish to fire once the leader completes lap 3 and cut off the trailing vehicle's rosbag before it logs "Lap 2 completed" — one of the two files would be missing the match.

- [ ] **Step 4: If Step 3 finds a short vehicle log, increase laps and re-verify**

If one vehicle's log is missing "Lap 2 completed", the multi-vehicle Finish is leader-triggered. Increase `--laps` in the affected `-quick` script(s) by 1 (e.g. `3` → `4`) and the corresponding shell-level `timeout` by a proportional buffer (e.g. add ~65s, matching the per-lap pace implied by `trial-quick.sh`'s existing 200s/3-lap ratio), commit the adjustment, then re-run Step 2-3 to confirm both vehicles now log the expected lap count. Apply the same adjustment ratio to the corresponding full-length script (`trial2.sh`/`trial3.sh`) even though Step 2 only exercises the quick variant, since both share the same Finish-triggering behavior.

- [ ] **Step 5: Confirm teardown**

Run: `docker compose ps` and `for p in 1 2 3 4; do docker compose -p $$p ps; done`
Expected: no running containers (the Makefile target's own `make down` call should have already handled this — this step just confirms it actually did, since Step 2 was the first real-world exercise of this target).

- [ ] **Step 6: Report results and commit if Step 4 changed anything**

If Step 4 required changes:

```bash
git add aichallenge/simulator_scripts/trial2-quick.sh aichallenge/simulator_scripts/trial3-quick.sh aichallenge/simulator_scripts/trial2.sh aichallenge/simulator_scripts/trial3.sh
git commit -m "fix: increase laps to account for leader-triggered multi-vehicle Finish"
```

If Step 4 was not needed, no commit for this task — just report the successful verification (rosbag paths, lap counts confirmed) to the user.

---

## Self-Review

**Spec coverage:** the spec's "含む" list (2台・3台 × 本編/quick の4ターゲット、per-vehicle rosbag recording) is covered by Tasks 1-2; the spec's "未解決の懸念" (leader-triggered Finish uncertainty) is covered by Task 3 Steps 3-4; the spec's explicit non-goals (no analyze/MLflow, no trial4) are respected — no task adds either. The spec's git-workflow requirement (isolated worktree) was already satisfied when this plan and its spec were committed to `.claude/worktrees/multi-vehicle-trial-targets` on branch `feat/multi-vehicle-trial-targets`.

**Placeholder scan:** no TBD/TODO; every step has complete file content, exact commands, or exact expected output.

**Type consistency:** N/A (this plan is shell/Makefile, not typed code) — checked instead that the vehicle-count loop (`for p in 1 2` / `1 2 3`), lap counts (7/3), and timeout values (600/200, shell-level 800/400) are consistent between each script's content (Task 1) and its corresponding Makefile target's echo messages and `SIM_MODE` value (Task 2).
