#!/bin/bash

AWSIM_DIRECTORY=/aichallenge/simulator/AWSIM
export ROS_DOMAIN_ID=0

# 3-lap run (2 measured laps) for quick exploration.  Running 3 laps ensures
# "Lap 2 completed" is logged before Finish fires.
# Shell-level hard cap: countdown (10 s) + AWSIM --timeout (200 s) + init/buffer (~190 s) = 400 s.
exec timeout 400 "$AWSIM_DIRECTORY/AWSIM.x86_64" \
    --start-mode count \
    --start-count-seconds 10 \
    --vehicles 1 \
    --npcs 0 \
    --boosts 5 \
    --laps 3 \
    --timeout 200 \
    --steer-source ackermann \
    --sound off \
    --collisions on \
    --handicap off \
    --wall-recovery on \
    --ranking off \
    --camera off \
    --lidar off \
    -headless

# Cameraを使う場合 : --camera cpu or gpu
# LiDARを使う場合 : --lidar cpu or gpu
