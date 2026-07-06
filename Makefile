# make file inspired by https://roborovsky-racers.github.io/RoborovskyNote/
SHELL := /bin/bash

.PHONY: autoware-build autoware-vehicle autoware-simulator autoware-request-initialpose autoware-request-control  awsim-request-start awsim-request-reset autoware-driver-zenoh autoware-driver-zenoh-rosbag trial trial-quick \
	simulator dev dev2 dev3 dev4 driver zenoh download rviz2 down down_all ps autoware-attach autoware-bash eval optuna optuna-apply \
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
	LOG_DIR=$(LOG_DIR) RUN_MODE=vehicle docker compose up -d autoware

# run autoware for simulator
autoware-simulator:
	@echo "Start Autoware for AWSIM"
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
# Blocks until AWSIM finishes, then runs make down + make analyze automatically.
# Exit 0 = all laps done; exit 124 = AWSIM --timeout fired (normal); other = crash (stop).
trial: SIM_MODE := trial
trial: simulator autoware-simulator
	@echo "[trial] AWSIM started (7 laps, ~10 min). Waiting for completion..."
	@docker compose wait simulator > /dev/null 2>&1; sim_exit=$$?; \
	if [ "$$sim_exit" -ne 0 ] && [ "$$sim_exit" -ne 124 ]; then \
	    echo "[trial] ERROR: AWSIM crashed (exit $$sim_exit). Run 'make down' manually."; \
	    exit "$$sim_exit"; \
	fi
	@$(MAKE) --no-print-directory -s down 2>/dev/null
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
# Blocks until AWSIM finishes, then runs make down + make analyze automatically.
# Exit 0 = all laps done; exit 124 = AWSIM --timeout fired (normal); other = crash (stop).
trial-quick: SIM_MODE := trial-quick
trial-quick: simulator autoware-simulator
	@echo "[trial-quick] AWSIM started (3 laps, ~5 min). Waiting for completion..."
	@docker compose wait simulator > /dev/null 2>&1; sim_exit=$$?; \
	if [ "$$sim_exit" -ne 0 ] && [ "$$sim_exit" -ne 124 ]; then \
	    echo "[trial-quick] ERROR: AWSIM crashed (exit $$sim_exit). Run 'make down' manually."; \
	    exit "$$sim_exit"; \
	fi
	@$(MAKE) --no-print-directory -s down 2>/dev/null
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

gate1: SIM_MODE := gate1
gate2: SIM_MODE := gate2
gate3: SIM_MODE := gate3
gate1 gate2 gate3: simulator autoware-simulator
	@echo "Start safety gate simulation (AWSIM + Autoware)"
	@echo "To stop: make down  (docker compose down --remove-orphans)"

eval:
	@echo "Start evaluation simulation (AWSIM + Autoware)"
	docker compose up -d autoware-simulator-evaluation
	$(MAKE) awsim-request-start
	@echo "To stop: make down  (docker compose down --remove-orphans)"

# remote operation (docker compose up -d rviz2)
rviz2:
	docker compose stop rviz2
	docker compose up -d rviz2

# driver + autoware + zenoh
autoware-driver-zenoh:
	LOG_DIR=$(LOG_DIR) RUN_MODE=vehicle docker compose up -d driver autoware
	sleep 15
	LOG_DIR=$(LOG_DIR) docker compose up -d zenoh

# driver + autoware + all-topic rosbag + zenoh
autoware-driver-zenoh-rosbag:
	LOG_DIR=$(LOG_DIR) RUN_MODE=vehicle docker compose up -d driver autoware rosbag
	sleep 15
	LOG_DIR=$(LOG_DIR) docker compose up -d zenoh

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
