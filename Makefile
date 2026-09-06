# make file inspired by https://roborovsky-racers.github.io/RoborovskyNote/
SHELL := /bin/bash

.PHONY: autoware-build autoware-vehicle autoware-simulator autoware-request-initialpose autoware-request-control  awsim-request-start awsim-request-reset autoware-driver-zenoh autoware-driver-zenoh-rosbag setup-vehicle trial trial-quick \
	simulator dev dev2 dev3 dev4 driver zenoh download rviz2 down down_all ps autoware-attach autoware-bash eval e2e optuna optuna-apply \
	trial2 trial2-quick trial3 trial3-quick

# Used by docker-compose.yml for build/eval artifact ownership.
HOST_UID ?= $(shell id -u)
HOST_GID ?= $(shell id -g)
export HOST_UID HOST_GID
# Stop host shell's ROS_DOMAIN_ID from overriding .env via compose interpolation,
# but still honor an explicit `make foo ROS_DOMAIN_ID=N` command-line override.
unexport ROS_DOMAIN_ID
ifeq ($(origin ROS_DOMAIN_ID),command line)
export ROS_DOMAIN_ID
endif

TIMESTAMP := $(shell date +%Y%m%d-%H%M%S)
LOG_DIR := /output/$(TIMESTAMP)

# AWSIM never self-exits after FinishALL, and its --timeout does not fire once
# the race has finished (Issue #60). Without this watcher every trial-* run
# would idle until the shell-level hard cap in simulator_scripts/*.sh kills
# AWSIM (~3.5 min wasted per quick run, ~7 min per full trial). Poll awsim.log
# for FinishALL and stop the containers as soon as all laps are done.
# Simulator container exit is the fallback (crash, or the hard cap on a run
# that never finishes): exit 0/124 proceeds, other codes abort — after cleanup,
# so no containers are left to cross-talk with the next run. Ctrl-C during the
# wait also stops the containers.
# $(1) = label used in log messages (e.g. trial-quick)
define WAIT_AWSIM_THEN_DOWN
	@log="output/$(TIMESTAMP)/awsim.log"; label="$(1)"; \
	cleanup() { \
	    if ! $(MAKE) --no-print-directory -s down > /dev/null 2>&1; then \
	        echo "[$$label] WARNING: 'make down' failed. Run it manually and check 'docker ps'."; \
	    fi; \
	}; \
	trap 'echo ""; echo "[$$label] Interrupted. Stopping containers..."; cleanup; exit 130' INT TERM; \
	sim_exit=""; \
	while :; do \
	    if grep -aqF "state → FinishALL" "$$log" 2>/dev/null; then \
	        echo "[$$label] All laps completed. Stopping containers..."; \
	        break; \
	    fi; \
	    cid=$$(docker compose ps -aq simulator 2>/dev/null | head -1); \
	    if [ -z "$$cid" ]; then \
	        echo "[$$label] WARNING: simulator container disappeared. Stopping..."; \
	        break; \
	    fi; \
	    st=$$(docker inspect -f '{{.State.Status}} {{.State.ExitCode}}' "$$cid" 2>/dev/null); \
	    case "$$st" in exited*) sim_exit="$${st#exited }"; break ;; esac; \
	    sleep 2; \
	done; \
	trap - INT TERM; \
	if [ -n "$$sim_exit" ] && [ "$$sim_exit" -ne 0 ] && [ "$$sim_exit" -ne 124 ]; then \
	    echo "[$$label] ERROR: AWSIM exited unexpectedly (exit $$sim_exit). Logs: output/$(TIMESTAMP)"; \
	    cleanup; \
	    exit "$$sim_exit"; \
	fi; \
	cleanup
endef

# make simulator-<mode>: <mode> は simulator_scripts/*.sh のファイル名
SIM_MODES := $(notdir $(basename $(wildcard aichallenge/simulator_scripts/*.sh)))
# dev<N>（車両数）/ gate<N>（テスト番号）は run_simulator.bash が展開するエイリアス
SIM_MODES += dev2 dev3 dev4 gate1 gate2 gate3
.PHONY: $(addprefix simulator-,$(SIM_MODES))
$(addprefix simulator-,$(SIM_MODES)): simulator-%:
	@$(MAKE) simulator SIM_MODE=$*

# autowareのbuildのみ
autoware-build:
	docker compose run -T --rm --no-deps autoware-build

# run autoware for vehicle
autoware-vehicle:
	@echo "Start Autoware for Vehicle"
	@echo "Log dir: .$(LOG_DIR)"
	LOG_DIR=$(LOG_DIR) RUN_MODE=vehicle docker compose up -d autoware

# run autoware for simulator
autoware-simulator:
	@echo "Start Autoware for AWSIM"
	@echo "Log dir: .$(LOG_DIR)"
	@LOG_DIR=$(LOG_DIR) RUN_MODE=awsim docker compose up -d autoware 2>/dev/null

# autoware command service use ROS_DOMAIN_ID from .env
autoware-request-initialpose:
	CMD="ros2 service call /set_initial_pose std_srvs/srv/Trigger '{}'" docker compose run --rm --no-deps autoware-command

autoware-request-control:
	CMD="ros2 topic pub -1 /awsim/control_mode_request_topic std_msgs/msg/Bool '{data: true}'" docker compose run --rm --no-deps autoware-command

# awsim admin service use ROS_DOMAIN_ID 0
awsim-request-start:
	CMD="env ROS_DOMAIN_ID=0 ros2 topic pub -1 /admin/awsim/start std_msgs/msg/Bool '{data: true}'" docker compose run --rm --no-deps autoware-command

awsim-request-reset:
	CMD="env ROS_DOMAIN_ID=0 ros2 topic pub -1 /admin/awsim/reset std_msgs/msg/Empty '{}'" docker compose run --rm --no-deps autoware-command

# run simulator (docker compose up -d simulator)
simulator:
	@echo "Start AWSIM (SIM_MODE=$(SIM_MODE))"
	@echo "Log dir: .$(LOG_DIR)"
	@LOG_DIR=$(LOG_DIR) SIM_MODE="$(SIM_MODE)" ROS_DOMAIN_ID=0 docker compose up -d simulator 2>/dev/null

# racing kart (docker compose up -d driver)
driver:
	docker compose up -d driver

# zenoh (docker compose up -d zenoh)
zenoh:
	docker compose up -d zenoh

dev: SIM_MODE := dev
dev: simulator autoware-simulator
	@echo "Start dev simulation (AWSIM + Autoware)"
	@echo "To stop: make down  (docker compose down --remove-orphans)"

# 6 measured laps on dev image (runs 7 laps; records /mpc/stats; no d1-result-details.json)
# Waits for FinishALL in awsim.log, then runs make down + make analyze automatically.
trial: SIM_MODE := trial
trial: simulator autoware-simulator
	@echo "[trial] AWSIM started (7 laps, ~7 min). Waiting for all laps (FinishALL)..."
	$(call WAIT_AWSIM_THEN_DOWN,trial)
	@OUTPUT="output/$(TIMESTAMP)/d1"; \
	if (cd racingkart-analysis && make --no-print-directory analyze OUTPUT="../$${OUTPUT}" COMMAND=trial LAPS=6); then \
	    echo "[trial] Done. → https://racingkart-results.pages.dev/runs/"; \
	else \
	    echo ""; \
	    echo "[trial] ERROR: analyze failed. Your data is saved at: $${OUTPUT}"; \
	    echo "  Retry: cd racingkart-analysis && make analyze OUTPUT=\"../$${OUTPUT}\" COMMAND=trial LAPS=6"; \
	    echo "  Docs:  racingkart-analysis/docs/ops/fly-mlflow-setup.md"; \
	    exit 1; \
	fi

# 2 measured laps on dev image (runs 3 laps; records /mpc/stats; quick exploration)
# Waits for FinishALL in awsim.log, then runs make down + make analyze automatically.
trial-quick: SIM_MODE := trial-quick
trial-quick: simulator autoware-simulator
	@echo "[trial-quick] AWSIM started (3 laps, ~3.5 min). Waiting for all laps (FinishALL)..."
	$(call WAIT_AWSIM_THEN_DOWN,trial-quick)
	@OUTPUT="output/$(TIMESTAMP)/d1"; \
	if (cd racingkart-analysis && make --no-print-directory analyze OUTPUT="../$${OUTPUT}" COMMAND=trial-quick LAPS=2); then \
	    echo "[trial-quick] Done. → https://racingkart-results.pages.dev/runs/"; \
	else \
	    echo ""; \
	    echo "[trial-quick] ERROR: analyze failed. Your data is saved at: $${OUTPUT}"; \
	    echo "  Retry: cd racingkart-analysis && make analyze OUTPUT=\"../$${OUTPUT}\" COMMAND=trial-quick LAPS=2"; \
	    echo "  Docs:  racingkart-analysis/docs/ops/fly-mlflow-setup.md"; \
	    exit 1; \
	fi

dev2: SIM_MODE := dev2
dev3: SIM_MODE := dev3
dev4: SIM_MODE := dev4
dev2 dev3 dev4: simulator
	@N=$(@:dev%=%); \
	echo "Start $$N-vehicle dev (autoware on ROS_DOMAIN_ID 1..$$N via docker compose -p)"; \
	for p in $$(seq 1 $$N); do LOG_DIR=$(LOG_DIR) ROS_DOMAIN_ID=$$p docker compose -p $$p up -d autoware; done; \
	echo "To Stop: make down"

# Per-vehicle MPC config for multi-vehicle trials (issue #104): MPC_CONFIG_<n>
# gives vehicle n an alternate MPC config (container path); unset vehicles keep
# the packaged default. Example (make a backmarker of vehicle 2):
#   make trial3 MPC_CONFIG_2=/aichallenge/workspace/src/aichallenge_submit/multi_purpose_mpc_ros_custom/multi_purpose_mpc_ros_custom/config/config_opponent_slow.yaml
MPC_CONFIG_1 ?=
MPC_CONFIG_2 ?=
MPC_CONFIG_3 ?=
# Time-domain MPCC opt-in (Step 5). Default false keeps the legacy MPC
# everywhere, so a plain `make trial*` and a race submission are unchanged.
# USE_MPCC=true runs the EGO (vehicle 1) on MPCC; opponents (2/3) always stay
# legacy so they can play backmarkers. For single-vehicle `make trial`, the
# exported var reaches the container via docker-compose's USE_MPCC passthrough.
#   make trial  USE_MPCC=true                          # solo on MPCC
#   make trial3 USE_MPCC=true MPC_CONFIG_2=<slow.yaml>  # MPCC ego vs slow opp
USE_MPCC ?= false
export USE_MPCC
# Self-play trials: vehicle 2 may also run MPCC (defense-role testing).
USE_MPCC_2 ?= false
export USE_MPCC_2
# Per-vehicle official-boost switch; defaults preserve today's behavior
# (launch-level default true for every vehicle).
USE_OFFICIAL_BOOST ?= true
export USE_OFFICIAL_BOOST
USE_OFFICIAL_BOOST_3 ?= $(USE_OFFICIAL_BOOST)
export USE_OFFICIAL_BOOST_3

# N-vehicle version of trial (7 laps; records /mpc/stats per vehicle).
# Waits for FinishALL, runs make down, then analyze-race → MLflow → dashboard publish.
trial2: SIM_MODE := trial2
trial2: simulator
	@echo "[trial2] AWSIM started (2 vehicles, 7 laps, ~7 min). Waiting for all laps (FinishALL)..."
	@for p in 1 2; do \
		case $$p in 1) cfg="$(MPC_CONFIG_1)";; 2) cfg="$(MPC_CONFIG_2)";; esac; \
		envp="LOG_DIR=$(LOG_DIR) ROS_DOMAIN_ID=$$p"; \
		[ -n "$$cfg" ] && envp="$$envp MPC_CONFIG_PATH=$$cfg"; \
		if [ "$$p" = "1" ]; then envp="$$envp USE_MPCC=$(USE_MPCC)"; elif [ "$$p" = "2" ]; then envp="$$envp USE_MPCC=$(USE_MPCC_2)"; else envp="$$envp USE_MPCC=false"; fi; \
		if [ "$$p" = "3" ]; then envp="$$envp USE_OFFICIAL_BOOST=$(USE_OFFICIAL_BOOST_3)"; else envp="$$envp USE_OFFICIAL_BOOST=$(USE_OFFICIAL_BOOST)"; fi; \
		env $$envp docker compose -p $$p up -d autoware; \
	done
	$(call WAIT_AWSIM_THEN_DOWN,trial2)
	@OUTPUT="output/$(TIMESTAMP)"; \
	if (cd racingkart-analysis && $(MAKE) --no-print-directory analyze-race OUTPUT="../$${OUTPUT}" COMMAND=trial2 LAPS=6); then \
	    echo "[trial2] Done. → https://racingkart-results.pages.dev/runs/"; \
	else \
	    echo ""; \
	    echo "[trial2] ERROR: analyze-race failed. rosbags saved at: $${OUTPUT}/d1, d2"; \
	    echo "  Retry: cd racingkart-analysis && make analyze-race OUTPUT=\"../$${OUTPUT}\" COMMAND=trial2 LAPS=6"; \
	    exit 1; \
	fi

# N-vehicle version of trial-quick (3 laps; quick exploration).
# Waits for FinishALL in awsim.log, then runs make down automatically.
trial2-quick: SIM_MODE := trial2-quick
trial2-quick: simulator
	@echo "[trial2-quick] AWSIM started (2 vehicles, 3 laps, ~3.5 min). Waiting for all laps (FinishALL)..."
	@for p in 1 2; do \
		case $$p in 1) cfg="$(MPC_CONFIG_1)";; 2) cfg="$(MPC_CONFIG_2)";; esac; \
		envp="LOG_DIR=$(LOG_DIR) ROS_DOMAIN_ID=$$p"; \
		[ -n "$$cfg" ] && envp="$$envp MPC_CONFIG_PATH=$$cfg"; \
		if [ "$$p" = "1" ]; then envp="$$envp USE_MPCC=$(USE_MPCC)"; elif [ "$$p" = "2" ]; then envp="$$envp USE_MPCC=$(USE_MPCC_2)"; else envp="$$envp USE_MPCC=false"; fi; \
		if [ "$$p" = "3" ]; then envp="$$envp USE_OFFICIAL_BOOST=$(USE_OFFICIAL_BOOST_3)"; else envp="$$envp USE_OFFICIAL_BOOST=$(USE_OFFICIAL_BOOST)"; fi; \
		env $$envp docker compose -p $$p up -d autoware; \
	done
	$(call WAIT_AWSIM_THEN_DOWN,trial2-quick)
	@OUTPUT="output/$(TIMESTAMP)"; \
	if (cd racingkart-analysis && $(MAKE) --no-print-directory analyze-race OUTPUT="../$${OUTPUT}" COMMAND=trial2-quick LAPS=2); then \
	    echo "[trial2-quick] Done. → https://racingkart-results.pages.dev/runs/"; \
	else \
	    echo ""; \
	    echo "[trial2-quick] ERROR: analyze-race failed. rosbags saved at: $${OUTPUT}/d1, d2"; \
	    echo "  Retry: cd racingkart-analysis && make analyze-race OUTPUT=\"../$${OUTPUT}\" COMMAND=trial2-quick LAPS=2"; \
	    exit 1; \
	fi

# N-vehicle version of trial (7 laps; records /mpc/stats per vehicle).
# Waits for FinishALL, runs make down, then analyze-race → MLflow → dashboard publish.
trial3: SIM_MODE := trial3
trial3: simulator
	@echo "[trial3] AWSIM started (3 vehicles, 7 laps, ~7 min). Waiting for all laps (FinishALL)..."
	@for p in 1 2 3; do \
		case $$p in 1) cfg="$(MPC_CONFIG_1)";; 2) cfg="$(MPC_CONFIG_2)";; 3) cfg="$(MPC_CONFIG_3)";; esac; \
		envp="LOG_DIR=$(LOG_DIR) ROS_DOMAIN_ID=$$p"; \
		[ -n "$$cfg" ] && envp="$$envp MPC_CONFIG_PATH=$$cfg"; \
		if [ "$$p" = "1" ]; then envp="$$envp USE_MPCC=$(USE_MPCC)"; elif [ "$$p" = "2" ]; then envp="$$envp USE_MPCC=$(USE_MPCC_2)"; else envp="$$envp USE_MPCC=false"; fi; \
		if [ "$$p" = "3" ]; then envp="$$envp USE_OFFICIAL_BOOST=$(USE_OFFICIAL_BOOST_3)"; else envp="$$envp USE_OFFICIAL_BOOST=$(USE_OFFICIAL_BOOST)"; fi; \
		env $$envp docker compose -p $$p up -d autoware; \
	done
	$(call WAIT_AWSIM_THEN_DOWN,trial3)
	@OUTPUT="output/$(TIMESTAMP)"; \
	if (cd racingkart-analysis && $(MAKE) --no-print-directory analyze-race OUTPUT="../$${OUTPUT}" COMMAND=trial3 LAPS=6); then \
	    echo "[trial3] Done. → https://racingkart-results.pages.dev/runs/"; \
	else \
	    echo ""; \
	    echo "[trial3] ERROR: analyze-race failed. rosbags saved at: $${OUTPUT}/d1, d2, d3"; \
	    echo "  Retry: cd racingkart-analysis && make analyze-race OUTPUT=\"../$${OUTPUT}\" COMMAND=trial3 LAPS=6"; \
	    exit 1; \
	fi

# N-vehicle version of trial-quick (3 laps; quick exploration).
# Waits for FinishALL in awsim.log, then runs make down automatically.
trial3-quick: SIM_MODE := trial3-quick
trial3-quick: simulator
	@echo "[trial3-quick] AWSIM started (3 vehicles, 3 laps, ~3.5 min). Waiting for all laps (FinishALL)..."
	@for p in 1 2 3; do \
		case $$p in 1) cfg="$(MPC_CONFIG_1)";; 2) cfg="$(MPC_CONFIG_2)";; 3) cfg="$(MPC_CONFIG_3)";; esac; \
		envp="LOG_DIR=$(LOG_DIR) ROS_DOMAIN_ID=$$p"; \
		[ -n "$$cfg" ] && envp="$$envp MPC_CONFIG_PATH=$$cfg"; \
		if [ "$$p" = "1" ]; then envp="$$envp USE_MPCC=$(USE_MPCC)"; elif [ "$$p" = "2" ]; then envp="$$envp USE_MPCC=$(USE_MPCC_2)"; else envp="$$envp USE_MPCC=false"; fi; \
		if [ "$$p" = "3" ]; then envp="$$envp USE_OFFICIAL_BOOST=$(USE_OFFICIAL_BOOST_3)"; else envp="$$envp USE_OFFICIAL_BOOST=$(USE_OFFICIAL_BOOST)"; fi; \
		env $$envp docker compose -p $$p up -d autoware; \
	done
	$(call WAIT_AWSIM_THEN_DOWN,trial3-quick)
	@OUTPUT="output/$(TIMESTAMP)"; \
	if (cd racingkart-analysis && $(MAKE) --no-print-directory analyze-race OUTPUT="../$${OUTPUT}" COMMAND=trial3-quick LAPS=2); then \
	    echo "[trial3-quick] Done. → https://racingkart-results.pages.dev/runs/"; \
	else \
	    echo ""; \
	    echo "[trial3-quick] ERROR: analyze-race failed. rosbags saved at: $${OUTPUT}/d1, d2, d3"; \
	    echo "  Retry: cd racingkart-analysis && make analyze-race OUTPUT=\"../$${OUTPUT}\" COMMAND=trial3-quick LAPS=2"; \
	    exit 1; \
	fi

# e2e は練習兼提出参考モード（e2e.sh）。e2e-final.sh は make simulator-e2e-final。
e2e: SIM_MODE := e2e
e2e: simulator autoware-simulator
	@echo "Start e2e simulation (AWSIM + Autoware)"
	@echo "To stop: make down  (docker compose down --remove-orphans)"

gate1: SIM_MODE := gate1
gate2: SIM_MODE := gate2
gate3: SIM_MODE := gate3
gate1 gate2 gate3: simulator autoware-simulator
	@echo "Start safety gate simulation (AWSIM + Autoware)"
	@echo "To stop: make down  (docker compose down --remove-orphans)"

# Evaluation run on the official eval image (6 laps, ~8 min), then the same
# analyze pipeline as trial (COMMAND=eval LAPS=6). The eval image bakes in
# /aichallenge and its run_evaluation.bash creates its own /output/<ts>/d1
# (LOG_DIR cannot be injected), so the run dir is discovered by scanning for
# the result files the autostart orchestrator writes after FinishALL
# (d1-result-details.json / result-summary.json / motion_analytics-*.html);
# only eval runs ever produce d1-result-details.json, so concurrent trial
# dirs can never match. The eval container does not self-exit after finish
# (Issue #60), hence the file watch instead of waiting on the container.
# Deadline: session_timeout (600 s) + AWSIM boot + result finalization,
# with margin.
eval:
	@echo "Start evaluation simulation (AWSIM + Autoware)"
	docker compose up -d autoware-simulator-evaluation
	$(MAKE) awsim-request-start
	@echo "[eval] AWSIM started (6 laps, ~8 min). Waiting for evaluation results..."
	@start_ts="$(TIMESTAMP)"; deadline=$$(( $$(date +%s) + 1500 )); \
	cleanup() { \
	    if ! $(MAKE) --no-print-directory -s down > /dev/null 2>&1; then \
	        echo "[eval] WARNING: 'make down' failed. Run it manually and check 'docker ps'."; \
	    fi; \
	}; \
	find_run_dir() { \
	    for d in $$(ls -1 output 2>/dev/null | grep -E '^[0-9]{8}-[0-9]{6}$$' | sort); do \
	        [ "$$d" \< "$$start_ts" ] && continue; \
	        if [ -f "output/$$d/d1/d1-result-details.json" ] \
	           && [ -f "output/$$d/d1/result-summary.json" ] \
	           && ls "output/$$d/d1/"motion_analytics-*.html > /dev/null 2>&1; then \
	            echo "$$d"; \
	            return 0; \
	        fi; \
	    done; \
	    return 1; \
	}; \
	trap 'echo ""; echo "[eval] Interrupted. Stopping containers..."; cleanup; exit 130' INT TERM; \
	run_dir=""; \
	while :; do \
	    if run_dir=$$(find_run_dir); then \
	        echo "[eval] Evaluation finished (output/$$run_dir). Stopping containers..."; \
	        break; \
	    fi; \
	    cid=$$(docker compose ps -aq autoware-simulator-evaluation 2>/dev/null | head -1); \
	    st=$$(docker inspect -f '{{.State.Status}}' "$$cid" 2>/dev/null); \
	    if [ -z "$$cid" ] || [ "$$st" = "exited" ]; then \
	        if run_dir=$$(find_run_dir); then \
	            echo "[eval] Evaluation finished (output/$$run_dir). Stopping containers..."; \
	            break; \
	        fi; \
	        echo "[eval] ERROR: eval container stopped without result files. Check logs under output/."; \
	        cleanup; \
	        exit 1; \
	    fi; \
	    if [ $$(date +%s) -ge $$deadline ]; then \
	        echo "[eval] ERROR: timed out waiting for evaluation results (25 min). Check logs under output/."; \
	        cleanup; \
	        exit 1; \
	    fi; \
	    sleep 2; \
	done; \
	trap - INT TERM; \
	cleanup; \
	OUTPUT="output/$$run_dir/d1"; \
	if (cd racingkart-analysis && $(MAKE) --no-print-directory analyze OUTPUT="../$$OUTPUT" COMMAND=eval LAPS=6); then \
	    echo "[eval] Done. → https://racingkart-results.pages.dev/runs/"; \
	else \
	    echo ""; \
	    echo "[eval] ERROR: analyze failed. Your data is saved at: $$OUTPUT"; \
	    echo "  Retry: cd racingkart-analysis && make analyze OUTPUT=\"../$$OUTPUT\" COMMAND=eval LAPS=6"; \
	    echo "  Docs:  racingkart-analysis/docs/ops/fly-mlflow-setup.md"; \
	    exit 1; \
	fi

# remote operation (docker compose up -d rviz2)
rviz2:
	docker compose stop rviz2
	docker compose up -d rviz2

# driver + autoware + zenoh
autoware-driver-zenoh:
	LOG_DIR=$(LOG_DIR) RUN_MODE=vehicle docker compose up -d driver autoware
	sleep 15
	LOG_DIR=$(LOG_DIR) docker compose up -d zenoh

setup-vehicle:
	@echo "Run vehicle setup check"
	@cd vehicle && ./setup_check.sh

# driver + autoware + all-topic rosbag + zenoh
autoware-driver-zenoh-rosbag:
	@echo "Run vehicle setup preflight check"
	@cd vehicle && ./setup_check.sh --phase preflight
	LOG_DIR=$(LOG_DIR) RUN_MODE=vehicle docker compose up -d driver autoware rosbag
	sleep 15
	LOG_DIR=$(LOG_DIR) docker compose up -d zenoh
	@echo "Run vehicle setup runtime check"
	@cd vehicle && ./setup_check.sh --phase runtime

down:
	@for p in 1 2 3 4; do docker compose -p $$p down --remove-orphans; done
	@docker compose down --remove-orphans

down_all:
	sudo docker ps -aq | xargs -r sudo docker rm -f

ps:
	@docker compose ps
	@for p in 1 2 3 4; do \
		out=$$(docker compose -p $$p ps --format '{{.Name}}\t{{.Service}}\t{{.Status}}' 2>/dev/null); \
		if [ -n "$$out" ]; then \
			echo "--- project=$$p ---"; \
			echo "$$out"; \
		fi; \
	done

autoware-attach:
	@./docker_exec.sh

autoware-bash:
	CMD="bash --rcfile /etc/skel/.bashrc -i" docker compose run --rm --no-deps autoware-command

# Optuna MPC parameter tuning → MLflow → Pages
# Usage: make optuna STUDY=mpc-q4 N=60
STUDY    ?= mpc-q4
N        ?= 60
optuna:
	@cd racingkart-analysis && $(MAKE) --no-print-directory optuna STUDY=$(STUDY) N=$(N)

# Apply best Optuna trial params to main config.yaml
# Usage: make optuna-apply STUDY=mpc-q4
optuna-apply:
	@cd racingkart-analysis && $(MAKE) --no-print-directory optuna-apply STUDY=$(STUDY)

# Download submission data by asking for credentials interactively
# Usage:
#   make download [SUBMISSION_ID=<id>]
# Usage (Only Admins):
#   make download [USER_ID=<id>] [SUBMISSION_ID=<id>]
download:
	@if [ -n "$(USER_ID)" ]; then \
		if [ -n "$(SUBMISSION_ID)" ]; then \
			vehicle/download_submission.sh --output aichallenge/workspace/src/ --user-id $(USER_ID) --submission-id $(SUBMISSION_ID); \
		else \
			vehicle/download_submission.sh --output aichallenge/workspace/src/ --user-id $(USER_ID); \
		fi; \
	else \
		if [ -n "$(SUBMISSION_ID)" ]; then \
			vehicle/download_submission.sh --output aichallenge/workspace/src/ --submission-id $(SUBMISSION_ID); \
		else \
			vehicle/download_submission.sh --output aichallenge/workspace/src/; \
		fi; \
	fi
