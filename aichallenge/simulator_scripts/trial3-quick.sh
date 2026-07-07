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
    --boosts 5 \
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
