---
marp: true
theme: gaia
paginate: true
size: 16:9
title: AI Challenge 2026 リポジトリ入門
description: このリポジトリの構造と基本操作を短時間で把握するための初学者向けスライド
style: |
  :root {
    --c-head: #0b3d5c; --c-accent: #1b9aaa; --c-text: #1b2733;
    --c-muted: #5b6b7a; --c-code-bg: #eef3f6; --c-rule: #d6e2ea;
  }
  section { font-size: 22px; color: var(--c-text); padding: 46px 56px; line-height: 1.45; background: #ffffff; }
  h1 { color: var(--c-head); font-size: 1.7em; }
  h2 { color: var(--c-head); border-bottom: 3px solid var(--c-accent); padding-bottom: .18em; font-size: 1.28em; }
  h3 { color: var(--c-accent); font-size: 1.05em; }
  strong { color: var(--c-head); }
  code { background: var(--c-code-bg); font-size: .85em; padding: .06em .35em; border-radius: 4px; }
  pre { font-size: .8em; line-height: 1.35; }
  ul, ol { margin: .25em 0; } li { margin: .12em 0; }
  table { font-size: .82em; } th { background: var(--c-head); color: #fff; }
  .columns { display: grid; grid-template-columns: 1fr 1fr; gap: 1.1em; }
  .small { font-size: .82em; } .muted { color: var(--c-muted); }
  section.lead { justify-content: center; text-align: left; }
  section::after { color: var(--c-muted); }
---

<!-- _class: lead -->

# AI Challenge 2026<br>リポジトリ入門（初学者向け）

- **対象:** このリポジトリを初めて触る人
- **目的:** 「どこに何があり、何から動かすか」を10分で把握する
- **ゴール:** 開発・評価・提出までの最短ルートを理解する

---

## このリポジトリでできること

- AWSIM + Autoware の実行環境を起動できる
- 開発実行 (`make dev`) と評価実行 (`make eval`) を使い分けられる
- 実行ログを `output/` に整理し、提出物を `submit/` に作れる
- シミュレータ運用から実車補助 (`vehicle/`, `remote/`) まで周辺ツールが揃っている

---

## まず覚える5コマンド

<div class="columns">

<div>

```bash
./docker_build.sh dev       # 開発用イメージをビルド（最初に1回）
make autoware-build         # Autoware/ROS 2 overlay をビルド
make dev                    # AWSIM + Autoware を開発モードで起動（1台）
make eval                   # 評価フローを一括実行
make down                   # コンテナ停止
```

</div>

<div>

- 迷ったらこの5つから始める
- セットアップは `./setup.bash bootstrap` で一括実行

### 実行順序（初回）
1. `./docker_build.sh dev`
2. `make autoware-build`
3. `make dev`
4. `make down`

</div>
</div>

---

## 全体像 (ホストとコンテナ)

1. ホストで `make` / `bash` コマンドを実行
2. `docker compose` が各サービスを起動
3. `simulator` (AWSIM) と `autoware` が連携
4. 結果は `output/` に保存、提出物は `submit/` に出力

---

## トップレベル構造

<div class="columns">

<div>

### コア
- `aichallenge/` — ビルド・起動・評価の中核
- `aichallenge/workspace/src/` — ROS 2 overlay のソース
- `aichallenge/simulator/` — AWSIM 実行データ
- `aichallenge/utils/` — publish/reset/rosbag などの補助スクリプト
- `aichallenge/simulator_scripts/` — シナリオ別 AWSIM 起動スクリプト

</div>

<div>

### 周辺・出力
- `vehicle/` — 実車向け補助スクリプト
- `remote/` — SSH/GUI など遠隔運用補助
- `docs/spec/` — 手順書・運用設計資料
- `output/` — 実行結果
- `submit/` — 提出アーカイブ

</div>
</div>

---

## `aichallenge/` の中で重要なもの

<div class="columns">

<div>

### 主要スクリプト
- `build_autoware.bash` — コンテナ内ビルド
- `run_simulator.bash` — AWSIM 起動（`simulator_scripts/<mode>.sh` に委譲）
- `run_autoware.bash` — Autoware 起動
- `run_evaluation.bash` — 評価スクリプト（コンテナ内から呼ばれる。直接実行しない）
- `simulator_scripts/` — シナリオ別スクリプト（dev, eval, gate, multiplay など）

</div>

<div>

### 補足
- ホストからの評価実行は `make eval`（= `docker compose up -d autoware-simulator-evaluation` + `awsim-request-start`）を使う
- 複数 Domain の並列起動は `make dev2` / `make dev3` / `make dev4` を使う

</div>
</div>

---

## 開発フロー (日常の反復)

<div class="columns">

<div>

### 手順
1. `aichallenge/workspace/src/` などを変更する
2. `make autoware-build` でビルド
3. `make dev` で動作確認
4. 問題があればログを確認 (`/output/latest/d1`)
5. `make down` で停止

</div>

<div>

### ポイント
- `make dev` は常駐プロセス。手動停止を忘れずに

</div>
</div>

---

## 評価フロー (提出前の確認)

<div class="columns">

<div>

### 手順
1. `./docker_build.sh eval --submit submit/aichallenge_submit.tar.gz` で評価用イメージを作成
2. `make eval` を実行（バックグラウンドで起動し、評価が自動進行する）
3. `output/<timestamp>/` に結果が保存される
4. `/output/latest/d1` で最新結果を確認
5. 終了後は **`make down` で停止**（自動で片付かない）

</div>

<div>

### シナリオを変えたいとき

```bash
SIM_MODE=gate1 make eval    # 安全ゲートシナリオ など
# 詳細は aichallenge/simulator_scripts/README.md 参照
```

</div>
</div>

---

## MPC 制御器（デフォルト制御器）

<div class="columns">

<div>

### 仕組み
- **LTV-MPC + OSQP** による最適制御（40 Hz）
- 参照軌跡 CSV（`env/final_ver3/traj_mincurv.csv`）を直接読み込み
- 状態: 横偏差 e_y・ヨー誤差 e_ψ・時刻 t
- 出力: 速度指令・ステア角 → `/control/command/control_cmd`

### 主要パラメータ（`config.yaml`）

| パラメータ | 現在値 | 役割 |
|---|---|---|
| `v_max` | 20 km/h | 速度上限 |
| `ay_max` | 6.5 m/s² | コーナー速度制限 |
| `Q[2]`（時間コスト） | 100,000 | 速さへのインセンティブ |

</div>

<div>

### 制御器の切り替え

```xml
<!-- reference.launch.xml -->
<arg name="control_method" default="mpc"/>
<!-- mpc / pure_pursuit / tiny_lidar_net / pilot_net -->
```

### リアルタイムチューニング

```bash
ros2 param set /mpc_controller v_max 25.0
ros2 param set /mpc_controller ay_max 7.5
```

### 統計ログ記録

`config.yaml` で `use_stats: true` にすると
`/mpc/stats`（solve 時間・infeasible 回数）が
rosbag に記録される

</div>
</div>

---

## 走行データ解析（racingkart-analysis）

<div class="columns">

<div>

### 位置づけ

- `racingkart-analysis/` はリポジトリ直下の **submodule**
- ROS・Docker **不要**（uv + Python のみ）
- `make eval` / `make trial` 後の `output/<timestamp>/d1/` を入力とする

### パイプライン

```
rosbag2_autoware/*.mcap
  → extract_rosbag.py
    → csv/kinematic_state.csv  (x, y, vx, e_y, lap, s)
    → csv/mpc_stats.csv        (solve_time_ms, ...)
  → analyze_results.py
    → run_*.json               (params + metrics + per_lap)
  → plot_summary.py
    → summary_*.html           (6 タブ HTML ダッシュボード)
```

</div>

<div>

### セットアップ

```bash
cd racingkart-analysis
make install          # uv で依存ライブラリ導入
```

### 実行例

```bash
uv run python scripts/extract_rosbag.py \
  ../output/20260601-234731/d1/

uv run python scripts/analyze_results.py \
  ../output/20260601-234731/d1/

uv run python scripts/plot_summary.py \
  ../output/20260601-234731/d1/
```

### ダッシュボード（6 タブ）

Overview / XY Map / Speed Profile /
Tracking / Time Series / Penalty

</div>
</div>

---

## Optuna 自動チューニング & 結果公開

<div class="columns">

<div>

### Optuna による自動チューニング

- **ベイズ最適化（TPE）** で MPC パラメータを自動探索
- `racingkart-analysis/optuna/` に一式
- 最適化目標: `avg_lap_2to6`（Lap2〜6 の平均タイム）
- 衝突あり試行は `TrialPruned` として除外

```python
# 探索パラメータ例
v_max:        [20.0, 30.0]
ay_max:       [6.5,  12.0]
Q[2]:         [1e5,  2e6]   (log scale)
wp_id_offset: [1, 4]
```

</div>

<div>

### 結果の公開（GitHub Pages）

```bash
# Optuna 結果を JSON に出力
uv run python scripts/generate_optuna_report.py ...

# racingkart-results に push → Pages 自動更新
uv run python scripts/publish_results.py \
  --study output/optuna_mpc/reports/study.json
```

### 公開先 URL

| リポジトリ | URL |
|---|---|
| racingkart-analysis | https://pathfinders-lab.github.io/racingkart-analysis/ |
| racingkart-results | https://keigo06.github.io/racingkart-results/ |

</div>
</div>

---

## GPU / CPU の切り替え

`.env` の `COMPOSE_FILE` で選択します。

```bash
# CPU + サウンド（デフォルト）
COMPOSE_FILE=docker-compose.yml:docker-compose.sound.yml

# GPU（NVIDIA）+ サウンド
COMPOSE_FILE=docker-compose.yml:docker-compose.gpu.yml:docker-compose.sound.yml
```

`./setup.bash env` を使うと GPU の有無を自動検出して `.env` を作成します。

---

## ログと提出物の見方

<div class="columns">

<div>

### `/output/latest/`
- 最新ランを格納する固定ディレクトリ
- `d1`/`d2`... 配下の固定名シンボリックリンクで成果物を参照する

</div>

<div>

### `submit/aichallenge_submit.tar.gz`
- `./create_submit_file.bash` で生成する提出用アーカイブ

</div>
</div>

---

## よくある詰まりどころ

<div class="columns">

<div>

### ビルド・起動
- **`install/setup.bash` がない** → `make autoware-build` を先に実行する
- **起動が不安定/止まらない** → `make down` で停止してから再実行

</div>

<div>

### 設定・マルチ台
- **Domain の設定が混乱している** → `ROS_DOMAIN_ID` を `.env` で設定する（デフォルト `1`）
- **複数台で動かしたい** → `make dev2` / `make dev3` / `make dev4` を使う

</div>
</div>

---

## どの資料から読むべきか

1. `docs/spec/how-to-setup.md`
2. `docs/spec/introduction.md`
3. このスライド (`docs/guide/beginner-deck.marp.md`)

- まずセットアップと基本実行の2本を押さえる

---

## まとめ

- 最初は「構造理解」より「実行して結果を見る」を優先
- 基本コマンドは `build -> dev -> eval -> down`
- ログは `/output/latest/d1`、提出物は `submit/`
- 慣れたら `vehicle/` と `remote/` に進む
