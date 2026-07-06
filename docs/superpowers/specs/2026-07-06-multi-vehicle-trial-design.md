# 複数車両版 trial（trial2/trial3）設計書

## 背景・目的

`make trial`/`make trial-quick` は単一車両（AWSIM 1台）を対象に、起動→周回数上限まで自動走行→自動片付け→解析（`racingkart-analysis`）まで一気通貫で行える「気軽に試せる」ターゲットになっている。

一方、複数車両（V2X回避・`RaceStateEstimator` 等の多車両戦略機能）を試すには現状 `make dev2`/`dev3`/`dev4` しかなく、これらは GUI 前提・周回数無制限・自動終了なしの対話的ターゲットで、`trial` 系のような気軽さがない。

本設計は、複数車両（2台・3台）を `trial`/`trial-quick` と同じ気軽さで試せる新規ターゲット `trial2`/`trial2-quick`/`trial3`/`trial3-quick` を追加する。

## スコープ

**含む:**
- 2台・3台それぞれについて、本編（7 laps）とお試し（3 laps）の headless・自動片付けターゲット
- 各車両（ROS_DOMAIN_ID 別）のrosbag自動記録（既存の `run_autoware.bash` の仕組みをそのまま利用）

**含まない（将来のPhase 2評価フレームワークで別途対応）:**
- 複数車両分の本格解析（順位・最接近距離・追い越し成否等の指標抽出）
- `racingkart-analysis` の analyze/MLflow 連携（単一車両向けの既存パイプラインとは送信先が混在するため、今回は呼ばない）
- 4台版（`trial4`）— 必要になれば同じパターンで追加できるが、今回は2台・3台のみ

## 新規ファイル

### `aichallenge/simulator_scripts/` に4本追加

`parallel.sh`（3台・レースプリセット）をベースに、既存の `README.md` に明記された「あえてモード別1ファイルにし、集約しない」という設計方針を踏襲してコピー＋修正する。

| ファイル | 台数 | laps | timeout | 測定周回 |
|---|---|---|---|---|
| `trial2.sh` | 2 | 7 | 600s | 6周分 |
| `trial2-quick.sh` | 2 | 3 | 200s | 2周分 |
| `trial3.sh` | 3 | 7 | 600s | 6周分 |
| `trial3-quick.sh` | 3 | 3 | 200s | 2周分 |

`parallel.sh` からの変更点（全4ファイル共通）:
- `--collisions off` → `--collisions on`（V2X回避・接近挙動を実際に衝突判定込みで検証するため）
- `--start-mode sync` → `--start-mode count --start-count-seconds 10`（`trial.sh`/`trial-quick.sh` と同じ10秒。`dev.sh`は5秒だが、複数台分のAutowareスタックが同時に立ち上がる一発勝負のターゲットなので、`trial`系と同じ長めの値を採用する。`/admin/awsim/start` の手動送信が不要になり「一発で完結する」という目的に合う）
- 末尾に `-headless` を追加（GPUの有無に関わらず確実にヘッドレス実行する）
- `--laps`/`--timeout` を上表の値に変更（`trial.sh`/`trial-quick.sh` と同じ 7/600・3/200 を踏襲。`parallel.sh` 本来の 6 laps/600s ではなく、単一車両版と同じ「N+1周指定してN周分のログを確実に記録する」ロジックを流用する）

`handicap on`・`ranking on`・`wall-recovery on`・`--vehicles N`・`--npcs 0`・`--boosts 2` は `parallel.sh` から変更しない。

### `Makefile` に4ターゲット追加

`trial`/`trial-quick` の「起動 → `docker compose wait simulator` → 正常性チェック → `make down`」という骨格と、`dev2/dev3/dev4` の「`for p in 1..N: ROS_DOMAIN_ID=$$p docker compose -p $$p up -d autoware`」という複数ドメイン起動の骨格を組み合わせる。

- `trial2`, `trial2-quick`: N=2 でループ
- `trial3`, `trial3-quick`: N=3 でループ

`RUN_MODE` は指定しない（デフォルトの `awsim` のままで、`run_autoware.bash` が `rosbag:=true` を含む launch 引数を組み立て、各ドメインが自分の `d${ROS_DOMAIN_ID}` ディレクトリへ自動でrosbagを記録する——この部分は完全に既存の仕組みに乗るだけで、新規ロジックは不要）。

`docker compose wait simulator` の終了コード判定・エラーメッセージ・`make down` 呼び出しは `trial`/`trial-quick` と同じパターンを踏襲する。analyze は呼ばない。成功時は、rosbagの保存先ディレクトリ（`output/<timestamp>/d1`, `d2`, `d3`）を案内するメッセージのみ表示する。

## データフロー

```
make trial2 (または trial2-quick / trial3 / trial3-quick)
  → docker compose up -d simulator (SIM_MODE=trial2 等)
      → run_simulator.bash trial2 → simulator_scripts/trial2.sh
          → AWSIM.x86_64 --vehicles N --collisions on --start-mode count -headless ...
  → for p in 1..N: docker compose -p $$p up -d autoware (ROS_DOMAIN_ID=$$p)
      → run_autoware.bash awsim $$p $(LOG_DIR)
          → aichallenge_system.launch.xml rosbag:=true ...
          → 出力: $(LOG_DIR)/d$$p/ (rosbag, autoware.log, ros home)
  → docker compose wait simulator (終了コード 0 or 124 を正常とみなす)
  → make down (p=1..4 ループで全ドメイン分片付け)
  → 案内メッセージ: rosbag保存先一覧を表示（analyzeは呼ばない）
```

## エラーハンドリング

`trial`/`trial-quick` と同一のパターンをそのまま踏襲する:
- `docker compose wait simulator` の終了コードが `0`（全周回完走）または `124`（`--timeout` 発火、正常）ならエラーなく `make down` に進む。
- それ以外の終了コード（クラッシュ）はエラーメッセージを出し、`make down` を手動で呼ぶよう促した上で非ゼロ終了する。
- `make down` は既に `for p in 1 2 3 4` でループする実装になっており、2台・3台どちらのケースも追加変更なしでカバーできる。

## 未解決の懸念（実装時に実機で確認する）→ 解決済み

- `ranking on`（複数車両レース）での「Finish」発火条件が単一車両と同じか未確認。先頭車がN周した時点で全車のrosbagが停止するのか、各車個別に停止するのかによっては、後方車のログが短くなる可能性がある。`trial.sh`/`trial-quick.sh` の「N+1周指定」がそのまま複数車両でも有効かは、実装後に一度ヘッドレス実行して各車のrosbagログを確認し、必要なら周回数を調整する。
- **結果（2026-07-06、`make trial2-quick`実機実行にて確認）**: 懸念は発生しなかった。d1・d2ともに`Lap 2 completed`がログに残り、後方車（d1）のログが短くなることはなかった（d2はLap 3まで完走、d1はLap 2で終了——いずれも正常な挙動）。周回数の調整（コンティンジェンシー）は不要だった。

## 検証方法

新規ターゲットは headless・周回数上限あり・`make down` による自動片付け付きのため、実装後にこのセッション内で実際に一度実行して確認できる（`make dev2` のような無期限・GUI前提の対話的ターゲットとは異なる）。具体的には `make trial2-quick`（2台・3周・timeout 200s・約5分）を1回実走し、`output/<timestamp>/d1` と `d2` それぞれにrosbagが記録され、`Lap 2 completed` ログが両方に残っているかを確認する。

ユーザーからは実行の許可を得ている。ただしこの開発環境は他セッションと共有されている可能性がある（本セッション中に親リポジトリのチェックアウトブランチが別セッションによって切り替わった事例を確認済み）ため、実行直前に一声かけてから進める。

## Gitワークフロー

本変更は親リポジトリ（`aichallenge-racingkart`）の `Makefile` と `aichallenge/simulator_scripts/` への変更であり、サブモジュールへの変更は含まない。現在の共有チェックアウトには別セッションの作業（`docs/beginner-guide-refactor` ブランチ、未コミットの可能性がある変更）が乗っているため、実装は `superpowers:using-git-worktrees` で独立したworktreeを切ってそちらで進め、他の作業と混在させない。
