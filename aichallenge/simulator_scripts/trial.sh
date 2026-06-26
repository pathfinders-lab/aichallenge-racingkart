#!/bin/bash

AWSIM_DIRECTORY=/aichallenge/simulator/AWSIM
export ROS_DOMAIN_ID=0

# 6-lap timed run with dev Autoware (custom MPC live-mounted).
# Uses --start-mode count so AWSIM auto-starts without a sync signal.
# Shell-level hard cap: countdown (10 s) + race timeout (600 s) + buffer (120 s) = 730 s.
exec timeout 730 "$AWSIM_DIRECTORY/AWSIM.x86_64" \
    --start-mode count \
    --start-count-seconds 10 \
    --vehicles 1 \
    --npcs 0 \
    --boosts 2 \
    --laps 6 \
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
