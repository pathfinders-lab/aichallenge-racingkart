#!/bin/bash

AWSIM_DIRECTORY=/aichallenge/simulator/AWSIM
export ROS_DOMAIN_ID=0

# 4-vehicle version of trial.sh (finals grid size, cf. e2e-final.sh): 7-lap run
# (6 measured laps + 1, so "Lap 6 completed" logs before Finish fires -- same
# reasoning as trial.sh/trial-quick.sh). Race preset (parallel.sh) with
# collisions on and count-mode start so `make trial4` completes unattended,
# unlike parallel.sh's sync-start (which waits for a manual /admin/awsim/start).
# Shell-level hard cap: countdown (10 s) + AWSIM --timeout (600 s) + init/buffer (~190 s) = 800 s.
exec timeout 800 "$AWSIM_DIRECTORY/AWSIM.x86_64" \
    --start-mode count \
    --start-count-seconds 10 \
    --vehicles 4 \
    --npcs 0 \
    --boosts 2 \
    --laps 7 \
    --timeout 600 \
    --steer-source ackermann \
    --sound off \
    --collisions on \
    --handicap on \
    --wall-recovery off \
    --ranking on \
    --camera off \
    --lidar off \
    -headless

# Cameraを使う場合 : --camera cpu or gpu
# LiDARを使う場合 : --lidar cpu or gpu
