# 公式提出結果の取り込みとログの扱い

> 仕様ドキュメント（現仕様の正）。文書運用方針は [docs/README.md](../README.md) を参照。

## 公式提出結果のダウンロードと取り込み

公式のAIチャレンジ提出・評価システムからダウンロードした走行結果
（`rosbag2_autoware.mcap` + `autoware.log`）は `submit_result/<id>/`
（`.gitignore` 済み、コミット不要）に手動でコピーする。フォルダ名は
ダウンロード時に割り当てられる UUID または epoch ミリ秒で、1フォルダ = 1レース。

ダウンロードできるのは常に自分（挑戦者）の1台分のみで、対戦相手（ライバル
スクリプト・NPC）のデータは含まれない（rosbagのトピック構成で確認済み:
`/clock`, `/control/command/control_cmd`, `/localization/acceleration`,
`/localization/kinematic_state` の4トピックのみ）。したがって
`racingkart-analysis` の多車両パイプライン（`analyze_race.py`）は使えず、
単一車両パイプライン（`extract_rosbag.py` → `analyze_results.py` →
`plot_summary.py` → `push_to_mlflow.py`）のみが対象になる。

`racingkart-analysis/scripts/import_submission.py` がこの一連の処理を
バッチで行う。詳しくは `racingkart-analysis/README.md` またはスクリプトの
docstring を参照。MLflow上では `command=submission-v1` タグと `team` タグ
（デフォルト `Pathfinders`、他チームのデータを取り込む場合は明示的に指定）
で通常のtrial/eval結果と区別する。

## 提出コードのバージョン記録とログの機密性

`create_submit_file.bash` は tar化前に、mpc submodule
（`multi_purpose_mpc_ros_custom`）の commit hash を
`multi_purpose_mpc_ros_custom/config/GIT_VERSION`（ビルド時生成、コミット
不要）に焼き込む。mpc submodule側の `mpc_controller.py` はこのファイルを
読み、起動時ログの内容を次のように切り替える:

- `GIT_VERSION` が無い（通常のローカル開発ビルド）→ 従来通り `config.yaml`/
  `ref_vel.yaml` の中身をフルダンプ
- `GIT_VERSION` があり `<hash>-dirty`（未コミット変更ありでパッケージング）→
  フルダンプ + commit id の両方を出力（再現性を優先。コミットせず提出すると
  ログにパラメータが残ることが、コミットを促すインセンティブにもなる）
- `GIT_VERSION` があり `<hash>`（クリーン）→ commit id だけを出力し、
  パラメータの中身は出さない

公式評価システム経由で `autoware.log` が他者に見える可能性があるため、
通常の（コミット済みでの）提出ではチューニングの詳細パラメータが漏洩しない。
自分たちの分析用には、`racingkart-analysis` の `extract_rosbag.py` が
commit id しか無いログから、mpc submoduleのローカルgit履歴を使って
（`git show <hash>:multi_purpose_mpc_ros_custom/config/config.yaml`）
`config_snapshot.yaml` を復元する。

## 提出時点でのMLflow事前登録

`create_submit_file.bash` は commit id の焼き込みに続けて、
`racingkart-analysis` の `make register-submission` を呼び出す。これは
mpc submoduleの作業ツリーから直接（redactionせず、自チームの私有MLflow
サーバーにしか送らないため）`config.yaml`/`ref_vel.yaml` を読み、
パラメータだけを記録した「pending」状態のMLflow runをその場で作成する。
返ってきた run_id は `multi_purpose_mpc_ros_custom/config/MLFLOW_RUN_ID`
にも焼き込まれ、`mpc_controller.py` が起動時ログに
`mlflow_run_id: <id>` として出力する。

これにより、公式評価システムからダウンロードした結果を取り込む際
（`import_submission.py`）、ログから run_id が見つかれば
`push_to_mlflow.py --run-id` でその同じrunにレース結果（メトリクス・
サマリー）を追記するだけになり、新規runを作る場合のように「どの提出が
どの結果に対応するか」をタイムスタンプで推測する必要がなくなる。
run_idがログに無い場合（旧形式の提出・他チームの提出など）は従来通り
新規runを作成する。

MLflowサーバーに到達できない・登録に失敗した場合、`create_submit_file.bash`
自体が失敗して提出tar.gzを作らない（提出物が記録なしで作られることを防ぐ
ため、あえて止める設計）。
