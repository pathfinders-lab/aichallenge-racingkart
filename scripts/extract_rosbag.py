#!/usr/bin/env python3
"""
rosbag から生データ CSV を出力する（Phase 1）。

Usage:
    python scripts/extract_rosbag.py <run_dir>
    例: python scripts/extract_rosbag.py output/20260601-234731/d1/

出力:
    <run_dir>/csv/kinematic_state.csv  -- 位置・速度・姿勢
    <run_dir>/csv/acceleration.csv     -- 加速度
    <run_dir>/csv/control_cmd.csv      -- ステア・速度・加速度指令
    <run_dir>/csv/config_snapshot.yaml -- autoware.log から抽出した config
"""

import argparse
import csv
import math
import re
import sys
from pathlib import Path

from rosbags.rosbag2 import Reader
from rosbags.typesys import Stores, get_typestore, get_types_from_idl

TOPIC_KINEMATIC = "/localization/kinematic_state"
TOPIC_ACCEL = "/localization/acceleration"
TOPIC_CMD = "/control/command/control_cmd"


def _quaternion_to_yaw(x: float, y: float, z: float, w: float) -> float:
    siny_cosp = 2.0 * (w * z + x * y)
    cosy_cosp = 1.0 - 2.0 * (y * y + z * z)
    return math.atan2(siny_cosp, cosy_cosp)


def _register_custom_types(typestore, connections: dict) -> None:
    """mcap スキーマに埋め込まれた IDL からカスタム型を登録する。"""
    sep = re.compile(r"={2,}\nIDL: [^\n]+\n")
    all_types = {}
    for conn in connections.values():
        blocks = sep.split(conn.msgdef)
        for block in blocks:
            block = block.strip()
            if not block:
                continue
            try:
                all_types.update(get_types_from_idl(block))
            except Exception:
                pass
    if all_types:
        typestore.register(all_types)


def _extract_config_snapshot(run_dir: Path, csv_dir: Path) -> None:
    """autoware.log から config.yaml ブロックを抽出して保存する。"""
    log_path = run_dir / "autoware.log"
    if not log_path.exists():
        print("  警告: autoware.log が見つかりません。config_snapshot.yaml をスキップします。", file=sys.stderr)
        return

    prefix = "[run_mpc_controller.bash-12] "
    lines = log_path.read_text().splitlines()
    config_lines: list[str] = []
    in_config = False

    for line in lines:
        if "----- config.yaml -----" in line:
            in_config = True
            continue
        if not in_config:
            continue
        if prefix in line:
            config_lines.append(line.split(prefix, 1)[1])
        else:
            # 別プロセスのログ行が来たらブロック終了
            break

    if config_lines:
        (csv_dir / "config_snapshot.yaml").write_text("\n".join(config_lines) + "\n")
        print(f"  config_snapshot.yaml: {len(config_lines)} 行")
    else:
        print("  警告: config.yaml ブロックが見つかりませんでした。", file=sys.stderr)


def extract(run_dir: Path) -> None:
    bag_dir = run_dir / "rosbag2_autoware"
    if not bag_dir.exists():
        print(f"エラー: {bag_dir} が見つかりません。", file=sys.stderr)
        sys.exit(1)

    csv_dir = run_dir / "csv"
    csv_dir.mkdir(exist_ok=True)

    typestore = get_typestore(Stores.ROS2_HUMBLE)

    kin_rows: list[list] = []
    accel_rows: list[list] = []
    cmd_rows: list[list] = []

    with Reader(bag_dir) as reader:
        connections = {c.topic: c for c in reader.connections}
        _register_custom_types(typestore, connections)

        target_conns = [
            c for c in reader.connections
            if c.topic in (TOPIC_KINEMATIC, TOPIC_ACCEL, TOPIC_CMD)
        ]

        for conn, timestamp, rawdata in reader.messages(connections=target_conns):
            ros_time = timestamp / 1e9  # ns → s
            msg = typestore.deserialize_cdr(rawdata, conn.msgtype)

            if conn.topic == TOPIC_KINEMATIC:
                pos = msg.pose.pose.position
                vel = msg.twist.twist.linear
                ang = msg.twist.twist.angular
                ori = msg.pose.pose.orientation
                yaw = _quaternion_to_yaw(ori.x, ori.y, ori.z, ori.w)
                kin_rows.append([ros_time, pos.x, pos.y, pos.z, vel.x, vel.y, yaw, ang.z])

            elif conn.topic == TOPIC_ACCEL:
                lin = msg.accel.accel.linear
                accel_rows.append([ros_time, lin.x, lin.y, lin.z])

            elif conn.topic == TOPIC_CMD:
                lat = msg.lateral
                lon = msg.longitudinal
                cmd_rows.append([ros_time, lat.steering_tire_angle, lon.speed, lon.acceleration])

    def write_csv(path: Path, header: list[str], rows: list[list]) -> None:
        with open(path, "w", newline="") as f:
            w = csv.writer(f)
            w.writerow(header)
            w.writerows(rows)

    write_csv(
        csv_dir / "kinematic_state.csv",
        ["ros_time", "x", "y", "z", "vx", "vy", "yaw", "yaw_rate"],
        kin_rows,
    )
    write_csv(
        csv_dir / "acceleration.csv",
        ["ros_time", "ax", "ay", "az"],
        accel_rows,
    )
    write_csv(
        csv_dir / "control_cmd.csv",
        ["ros_time", "steering_angle", "cmd_speed", "cmd_accel"],
        cmd_rows,
    )

    print(f"出力先: {csv_dir}")
    print(f"  kinematic_state.csv : {len(kin_rows):>6} 行")
    print(f"  acceleration.csv    : {len(accel_rows):>6} 行")
    print(f"  control_cmd.csv     : {len(cmd_rows):>6} 行")

    _extract_config_snapshot(run_dir, csv_dir)


def main() -> None:
    parser = argparse.ArgumentParser(
        description="rosbag から生データ CSV を出力する",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="例: python scripts/extract_rosbag.py output/20260601-234731/d1/",
    )
    parser.add_argument("run_dir", type=Path, help="d1/ などの run ディレクトリ")
    args = parser.parse_args()

    if not args.run_dir.exists():
        print(f"エラー: {args.run_dir} が見つかりません。", file=sys.stderr)
        sys.exit(1)

    extract(args.run_dir)


if __name__ == "__main__":
    main()
