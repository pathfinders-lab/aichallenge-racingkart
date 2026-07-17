# CLAUDE.md

## Project Overview

自動運転AIチャレンジ（aichallenge-racingkart）の開発リポジトリ。
Autoware Universe をベースとした自動運転ソフトウェアを開発し、レーシングカート（AWSIM シミュレータおよび実車）でタイムアタックを行う。

- フォーク元: https://github.com/AutomotiveAIChallenge/aichallenge-racingkart
- 自分のリポジトリ: https://github.com/pathfinders-lab/aichallenge-racingkart

## Stack

- **言語**: C++, Python, bash
- **フレームワーク**: ROS2 (Humble), Autoware Universe
- **シミュレータ**: AWSIM
- **インフラ**: Docker, Docker Compose
- **通信**: Zenoh (実車連携), CycloneDDS
- **CI/CD**: GitHub Actions

## Commands

- **dev**: `make dev` — 開発用コンテナ起動
- **build**: `make autoware-build` — Autoware のビルド
- **simulator**: `make simulator` — AWSIM シミュレータ起動
- **autoware (sim)**: `make autoware-simulator` — シミュレータ用 Autoware 起動
- **autoware (vehicle)**: `make autoware-vehicle` — 実車用 Autoware 起動
- **driver**: `make driver` — レーシングカートドライバー起動
- **zenoh**: `make zenoh` — Zenoh ブリッジ起動
- **down**: `make down` — コンテナ停止
- **pre-commit**: `pre-commit run -a` — コミット前チェック（必須）

## Conventions

- コミット前に必ず `pre-commit run -a` を実行してチェックを通す
- XML, YAML, シェルスクリプトのフォーマットは pre-commit で自動チェック
- ROS2 パッケージは `aichallenge/` 以下に配置
- Docker 関連は `docker-compose.yml` / `Dockerfile` を編集
- 実装計画書は `docs/plan/YYYY-MM-DD-<feature>.md` に保存（`.gitignore` 済み、コミット不要）
- PR マージ後または実装完了後に計画書ファイルを削除する（またはユーザーに削除を促す）
- 仕様書 (`docs/spec/`) は「現状」を記述する。1 トピック 1 ファイル。日付をファイル名に含めない
- 日付付きの詳細設計書（`docs/superpowers/` 以下の specs/plans）はローカル作業ファイルであり
  コミットしない（`.gitignore` 済み）。**設計書だけの PR は作らない**。
  設計の共有・記録は対応 Issue のコメントか `docs/spec/` の現状ドキュメント更新で行う
- `design_docs/` など `docs/` 以外への設計書作成は行わない

## Key Files

- `aichallenge/` — メイン開発ディレクトリ（ROS2パッケージ群）
- `aichallenge/README.md` — エントリポイントまとめ
- `docs/guide/development-process.md` — **開発プロセスの正**
  （チケット・設計・実装・検証・PR・提出・情報の三層）。本ファイルはその要約
- `docs/guide/beginner-deck.marp.md` — 基本操作・検証フローのガイド
  （build → dev → trial → down）。検証・実験の手順を組む前に必ず参照する
- `docker-compose.yml` — サービス定義（触る際は注意）
- `Dockerfile` — Autoware イメージ定義
- `vehicle/` — 実車環境向け設定
- `output/` — 実行ログ出力先（生成物、コミット不要）
- `submit/` — 提出物置き場

## Issue Workflow

- 今後やりたい作業は GitHub Issue としてチケット化する（まとまった作業 = 1 Issue +
  複数 PR。細かく割りすぎない。途中の PR は `Refs #N`、最後の PR で `Closes #N`）
- 検証したこと（実機 trial・ベンチマーク・調査など）の結果・ログ・判断は、
  対応する Issue のコメントに記録する
- PR 本文で対応 Issue を必ず参照する（完了させる場合は `Closes #N`、
  部分対応は `Refs #N`）
- Issue は変更が入るリポジトリに立てる（サブモジュール側の変更は
  サブモジュールのリポジトリへ。リポジトリ横断の作業は本リポジトリに立てて
  相互リンクする）

## Git Workflow

- Root Branch: develop
- 実装作業は git worktree（`.claude/worktrees/`）で隔離して行い、
  他の作業中の実装・ブランチ・ワーキングツリーに影響を与えない
- PR 前に必ず `git rebase origin/develop` を実行する
- PR 作成時は `Language > PR Description` に応じて
  `~/.claude/PULL_REQUEST_TEMPLATE/japanese.md` を
  `--body-file` で指定する
- マージは **Squash and Merge** のみ
- マージ後はブランチを削除する
- `main` は `upstream` の変更を反映させる場所とする（fork sync を行う）
- `upstream` (AutomotiveAIChallenge 公式) への push は絶対に行わない

## Guardrails

- シミュレーション（AWSIM 等）を起動する前に `docker ps` で確認し、
  別のシミュレーションが動いている間は実行しない
  （DDS のトピック混線で両方のセッションのデータが壊れるため）

## Language

- Code Comments: English
- Commit Messages: English
- PR Description: Japanese
- Issues: Japanese

## Commit Message

Conventional Commits 形式を使う。prefix（`feat:` `fix:` など）は英語固定。詳細は `/commit` を参照。
