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
    --c-muted: #5b6b7a; --c-code-fg: #1b2733; --c-code-bg: #eef3f6; --c-rule: #d6e2ea;
  }
  section { font-size: 22px; color: var(--c-text); padding: 46px 56px; line-height: 1.45; background: #ffffff; }
  h1 { color: var(--c-head); font-size: 1.7em; }
  h2 { color: var(--c-head); border-bottom: 3px solid var(--c-accent); padding-bottom: .18em; font-size: 1.28em; }
  h3 { color: var(--c-accent); font-size: 1.05em; }
  strong { color: var(--c-head); }
  :not(pre) > code { color: var(--c-code-fg); background: var(--c-code-bg); font-size: .85em; padding: .06em .35em; border-radius: 4px; }
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
- 開発実行 (`make dev`) / 計測 (`make trial`) / 評価実行 (`make eval`) を使い分けられる
- 実行ログを `output/` に整理し、提出物を `submit/` に作れる
- 走行データを解析・可視化し、Optuna で MPC パラメータを自動最適化できる（`racingkart-analysis/`）
- `make trial` 1コマンドで走行計測からダッシュボード反映まで自動完結（Cloudflare Pages）
- シミュレータ運用から実車補助 (`vehicle/`, `remote/`) まで周辺ツールが揃っている

---

## 初回セットアップ

```bash
# 1. サブモジュールを初期化（clone 直後に必須）
git submodule update --init --recursive

# 2. 解析ツールの Python 環境を構築
cd racingkart-analysis && make install && cd ..

# 3. 開発用 Docker イメージをビルド（初回のみ）
./docker_build.sh dev

# 4. Autoware/ROS 2 overlay をビルド（初回・ソース変更後）
make autoware-build
```

> `./setup.bash bootstrap` は Docker のインストールと `.env` 生成を行うもので、
> 上記の手順（submodule update / make install）は含まれない。この順番を手動で実行する。

---

## まず覚えるコマンド

```bash
make dev          # AWSIM + Autoware を開発モードで起動
make trial        # 6周計測 → 解析 → MLflow 記録まで自動
make trial-quick  # 2周の素早い計測
make optuna       # MPC パラメータを Bayesian 最適化（N 回自動試行）
make eval         # 評価実行 → 解析 → MLflow 記録まで自動（提出前の最終確認）
make down         # コンテナ停止
```

| | `make dev` | `make trial-quick` | `make trial` |
|---|---|---|---|
| 用途 | 動作確認 | 素早い探索 | ラップタイム計測 |
| 周回数 | 無制限 | 2周（3周走行） | 6周（7周走行） |
| MPC stats 記録 | なし | あり | あり |

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
- `racingkart-analysis/` — 走行データ解析ツール群（submodule）
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
- ホストからの評価実行は `make eval` を使う（評価コンテナ起動 → 完走待ち → `make down` → 解析まで自動）
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
- ラップタイムを計測したいときは `make dev` の代わりに `make trial` を使う

</div>
</div>

---

## 評価フロー (提出前の確認)

<div class="columns">

<div>

### 手順
1. `./docker_build.sh eval --submit submit/aichallenge_submit.tar.gz` で評価用イメージを作成
2. `make eval` を実行（6周の評価が完走するまで待機し、`make down` → 解析 → MLflow 記録まで自動）
3. `output/<timestamp>/` に結果が保存される
4. `/output/latest/d1` で最新結果を確認

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

## 公式提出フロー（提出 → 結果の取り込み）

<div class="columns">

<div>

### 手順（ワンコマンド）
```bash
# mpc の任意コミットを tar 化して提出まで（確認プロンプトあり）
./submit_from_mpc.bash <mpc-commit> -p "提出目的の短文"
# 提出せずゲート・サマリー確認だけしたいとき
./submit_from_mpc.bash <mpc-commit> --dry-run
```
1. origin/develop から隔離 worktree を作り、mpc だけ指定コミットへ
   （共有チェックアウトは触らない。worktree は終了時に自動削除）
2. MLflow に run を事前登録し `config/GIT_VERSION` /
   `config/MLFLOW_RUN_ID` を焼き込んで tar.gz 作成
3. サマリー（sha256・順位・当日提出数）を表示 → `yes` で提出
4. 成功すると `submit/.submission_log` に台帳追記
5. 評価完了後: `cd racingkart-analysis && make sync-board`
   → 結果・rosbag を自動取得し、事前登録した run に解析付きで追記

</div>

<div>

### 補足
- 認証は `racingkart-analysis/.env` に `AIC_BOARD_USERNAME` /
  `AIC_BOARD_PASSWORD` を書く（MLflow 設定と同じ場所、gitignore 済み）。
  **親リポ直下の `.env` は git 追跡されているので書かないこと**
- 提出は**1日10回の評価枠を消費**する。3分間隔・当日上限は
  ツールが自己チェックして超過前にブロックする
- **エラーが出ても即再実行しない**（再実行=新規提出）。
  まずボードを確認してから判断する
- 旧手動フロー（tar のみ作成）は `./create_submit_file.bash`
- 詳しくは `docs/spec/submission-tracking.md` を参照

</div>
</div>

---

## チューニングフロー（make trial → ダッシュボード）

<div class="columns">

<div>

### 手順
1. `make trial` を実行（6 周計測 → 解析 → MLflow 記録 まで自動）
2. 結果ダッシュボードに自動反映（`gh` 認証済みなら即時、未認証は1時間以内）
   → https://racingkart-results.pages.dev/runs/

**1コマンドで完結。** `make analyze` の手動実行は不要。

> 即時反映には `gh auth login` が必要（未認証でも1時間以内に自動同期）

</div>

<div>

### `make dev` との違い

| | `make dev` | `make trial-quick` | `make trial` |
|---|---|---|---|
| 用途 | 動作確認 | 素早い探索 | ラップタイム計測 |
| 周回数 | 無制限 | 2周（3周走行） | 6周（7周走行） |
| MPC stats 記録 | なし | あり | あり |
| eval イメージ | 不要 | 不要 | 不要 |

`make trial-quick` も同様に1コマンドでダッシュボードまで自動連携

</div>
</div>

---

## Optuna 自動最適化

<div class="columns">

<div>

### 手順
1. 最適化を実行（シミュレータ起動・MLflow記録・Pages公開まで自動）
   ```bash
   make optuna STUDY=mpc-q4 N=60
   ```
2. 完了後、best params を config.yaml に適用
   ```bash
   make optuna-apply STUDY=mpc-q4
   # → diff 確認後 make trial で検証
   ```
3. 進捗をリアルタイム確認したい場合（別ターミナル）
   ```bash
   cd racingkart-analysis
   uv run optuna-dashboard \
     sqlite:///output/optuna_mpc/mpc_tuning.db
   # → http://localhost:8080
   ```

</div>

<div>

### ポイント
- `make trial` の**自動多試行版**（N 回走行してパラメータを探索）
- **ベイズ最適化（TPE）** で効率的に収束
- 同じ `--study-name` で途中再開可能
- 最適化対象: MPC コスト行列（Q, QN, R）
- 各 trial の結果は MLflow に自動記録 → Pages に反映

### チームの最新結果
- Dashboard: https://racingkart-results.pages.dev/
- Runs 比較: https://racingkart-results.pages.dev/runs/
- Studies: https://racingkart-results.pages.dev/studies/

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

### セットアップ
- **サブモジュールが空 / 古い** → `git submodule update --init --recursive` を実行する
- **`uv` が見つからない / 解析ツールが動かない** → `cd racingkart-analysis && make install` を実行する
- **`install/setup.bash` がない** → `make autoware-build` を先に実行する

</div>

<div>

### 起動・設定
- **起動が不安定 / 止まらない** → `make down` で停止してから再実行
- **Domain の設定が混乱している** → `ROS_DOMAIN_ID` を `.env` で設定する（デフォルト `1`）
- **複数台で動かしたい** → `make dev2` / `make dev3` / `make dev4` を使う

</div>
</div>

---

## どの資料から読むべきか

1. このスライド（全体像と基本操作の把握）
2. `docs/spec/how-to-setup.md`（詳細なセットアップ手順）
3. `docs/spec/introduction.md`（アーキテクチャの詳細）

- まずこのスライドで全体像を掴み、次にセットアップ手順を読む

---

## まとめ

- 最初は「構造理解」より「実行して結果を見る」を優先
- 初回は `git submodule update` と `make install` を忘れずに
- 基本コマンドは `build → dev → trial → down`
- ログは `/output/latest/d1`、提出物は `submit/`
- 慣れたら `vehicle/` と `remote/` に進む
