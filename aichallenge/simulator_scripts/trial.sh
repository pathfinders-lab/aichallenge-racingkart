#!/bin/bash

AWSIM_DIRECTORY=/aichallenge/simulator/AWSIM
export ROS_DOMAIN_ID=0

# 7-lap run with dev Autoware (custom MPC live-mounted).  Running 7 laps ensures
# that "Lap 6 completed" is logged before Finish fires, so analysis can use the
# accurate MPC-controller lap times instead of kinematic-based estimation.
# Shell-level hard cap: countdown (10 s) + 7 laps (~500 s) + buffer (120 s) = 630 s.
exec timeout 800 "$AWSIM_DIRECTORY/AWSIM.x86_64" \
    --start-mode count \
    --start-count-seconds 10 \
    --vehicles 1 \
    --npcs 0 \
    --boosts 2 \
    --laps 7 \
    --timeout 600 \
    --steer-source ackermann \
    --sound off \
    --collisions on \
    --handicap off \
    --wall-recovery off \
    --ranking off \
    --camera off \
    --lidar off

# Cameraを使う場合 : --camera cpu or gpu
# LiDARを使う場合 : --lidar cpu or gpu
# GPUがない場合 -headlessを末尾に追加
