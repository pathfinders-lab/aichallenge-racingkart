# rosbag 抽出・解析パイプライン 設計書

**作成日**: 2026-06-02  
**対象**: aichallenge-racingkart の走行データ抽出・解析パイプライン

---

## 概要

`make eval` 後に生成される rosbag から、ROS 環境なしで解析できる形式（CSV）にデータを変換し、速度プロファイル・横方向誤差(e_y)・ペナルティ発生位置などのメトリクスを計算するパイプライン。

---

## アーキテクチャ

2段構成とする。

```
[Stage 1] extract_rosbag.py   rosbag2_autoware/ → csv/
[Stage 2] analyze_results.py  csv/ + JSON + 参照軌跡 → run_*.json
```

Stage 1 は `rosbags`（純 Python ライブラリ）でホストから直接実行できる（Docker 不要）。  
Stage 2 は pandas / numpy のみで動作する。

### ディレクトリ構成

```
output/<timestamp>/d1/
├── rosbag2_autoware/          ← 入力（rosbags.Reader でディレクトリごと渡す）
│   ├── metadata.yaml
│   └── rosbag2_autoware_0.mcap
├── d1-result-details.json     ← 入力（ペナルティ・公式ラップタイム）
├── result-summary.json        ← 入力（複数台時の順位）
├── autoware.log               ← 入力（config.yaml・MPC側ラップタイム）
├── csv/                       ← extract の出力
│   ├── kinematic_state.csv
│   ├── acceleration.csv
│   ├── control_cmd.csv
│   └── config_snapshot.yaml
└── run_<timestamp>.json       ← analyze の出力
```

---

## 入力ファイルの整理

| ファイル | 提供できる情報 | 注意点 |
|---|---|---|
| `rosbag2_autoware/` | 位置(x,y,z)・速度・加速度・ステア指令・ROS タイムスタンプ | ディレクトリごと `rosbags.Reader` に渡す（`.mcap` 単体は不可） |
| `autoware.log` | ラップタイム（MPC側）・config.yaml 全内容・参照軌跡パス | config は起動時に全文出力される |
| `d1-result-details.json` | ペナルティ発生時刻(race_time)・種別・継続秒数・AWSIM側ラップタイム | race_time は「レース開始からの秒数」 |
| `result-summary.json` | 複数台レース時の順位・全体サマリー | 1台走行では result-details で十分 |
| 参照軌跡 CSV | コース形状の (x,y)・曲率・速度制限 | autoware.log の `reference_path.csv_path` から解決 |
| `capture.mp4` | 走行映像 | このパイプラインでは使わない |
| `motion_analytics.html` | AWSIM 生成の速度・加速度グラフ | 参照用、このパイプラインでは使わない |

### タイムスタンプの対応関係

`d1-result-details.json` の `race_time` と rosbag の ROS タイムスタンプは別スケール:

```
rosbag 開始時刻 = kinematic_state の最初の ros_time（例: 1780325269.8 s）
ペナルティ位置 = rosbag開始時刻 + race_time → kinematic_state の最近傍行 → (x, y)
```

### ラップタイムの出所

| 出所 | 特徴 | 用途 |
|---|---|---|
| `autoware.log`（MPC側） | ペナルティなしの純粋な走行時間 | 参考値 |
| `d1-result-details.json`（AWSIM側） | ペナルティ込みの公式タイム | 評価基準 |

---

## Stage 1: `extract_rosbag.py`

### 呼び出し方

```bash
python scripts/extract_rosbag.py output/20260601-234731/d1/
```

### 処理内容

1. `rosbag2_autoware/` ディレクトリを `rosbags.Reader` で開く
2. 3トピックを CSV に書き出す（`/clock` は除外）
3. `autoware.log` から `config.yaml` ブロックを抽出 → `csv/config_snapshot.yaml` に保存

### 出力 CSV カラム

| ファイル | カラム |
|---|---|
| `kinematic_state.csv` | `ros_time, x, y, z, vx, vy, yaw, yaw_rate, s, e_y` |
| `acceleration.csv` | `ros_time, ax, ay, az` |
| `control_cmd.csv` | `ros_time, steering_angle, cmd_speed, cmd_accel` |

`s`（進行距離）と `e_y`（横方向誤差）は extract 時に参照軌跡 CSV との最近傍計算で求める。  
参照軌跡パスは `autoware.log` 内の config から取得し、`aichallenge/workspace/install/multi_purpose_mpc_ros/share/multi_purpose_mpc_ros/<csv_path>` として解決する。

### 依存ライブラリ

```
rosbags >= 0.10.6
numpy（e_y 計算用）
```

---

## Stage 2: `analyze_results.py`

### 呼び出し方

```bash
python scripts/analyze_results.py output/20260601-234731/d1/
```

### 処理内容

1. `csv/kinematic_state.csv`（s, e_y 込み）・`acceleration.csv`・`control_cmd.csv` を読む
2. `d1-result-details.json` からペナルティ events を読む
3. 計算:
   - ペナルティ発生 (x,y): race_time → ROS タイムスタンプ → kinematic_state の最近傍行
4. 集計して `run_<timestamp>.json` を出力

### 出力 `run_*.json` のメトリクス

```json
{
  "run_id": "<timestamp>",
  "source": "local",
  "params": { },
  "metrics": {
    "lap_times": [66.24, 65.35, 79.65, 65.25, 66.13, 65.42],
    "best_lap": 65.25,
    "avg_lap_2to6": 68.37,
    "penalty_count": 2,
    "penalty_total_seconds": 6.26,
    "max_speed_kmh": null,
    "avg_speed_kmh": null,
    "max_ey_m": null,
    "rms_ey_m": null
  },
  "profiles": {
    "speed_by_distance": [],
    "ey_by_distance": [],
    "trajectory_xy": [],
    "penalty_positions": []
  }
}
```

### 依存ライブラリ

```
pandas, numpy, pyyaml
```

---

## 実装の進め方

段階的に実装する。各フェーズは独立して動作確認できる。

| フェーズ | 内容 | 完了基準 |
|---|---|---|
| 1 | `extract_rosbag.py`: rosbag → CSV（x, y, vx 等の生データ） | CSV が正しく生成される |
| 2 | `extract_rosbag.py`: s・e_y の計算を追加（参照軌跡との最近傍） | kinematic_state.csv に s, e_y が含まれる |
| 3 | `analyze_results.py`: CSV + d1-result-details.json → metrics 集計 | `run_*.json` の metrics セクションが埋まる |
| 4 | `analyze_results.py`: ペナルティ発生位置 (x,y) 特定 + profiles | profiles・penalty_positions が埋まる |
