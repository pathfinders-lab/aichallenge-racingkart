# 混走 trial（速度差のある複数台検証）

`make trial3` / `make trial3-quick` で、車両ごとに別の MPC 設定を走らせて
速度差のある混走を再現できる。

## 使い方

```bash
# 通常（3 台とも同一設定）— 従来どおり
make trial3

# 車両 3 を中高速プリセット（~51s/lap）にして速度差をつける
make trial3 MPC_CONFIG_3=/aichallenge/workspace/src/aichallenge_submit/multi_purpose_mpc_ros_custom/multi_purpose_mpc_ros_custom/config/config_opponent_midspeed.yaml

# 3 台バラバラも可能（未指定の車両はパッケージ既定のまま）
make trial3-quick MPC_CONFIG_2=<container path> MPC_CONFIG_3=<container path>
```

FinishALL の自動検知・`make down`・rosbag 保存（`output/<timestamp>/d{1,2,3}/`）は
通常の trial3 と同じ。

## 仕組み

- `mpc.launch.xml` が `--config_path` を環境変数 `MPC_CONFIG_PATH` で上書き可能
  （未設定時は従来どおり `find-pkg-share` のパッケージ既定。`$(env VAR デフォルト)` の
  ネスト substitution は Humble で動作確認済み）
- `docker-compose.yml` は `MPC_CONFIG_PATH` を**値なし形式**で透過する。ホストで未設定なら
  コンテナでも未設定のままになり、launch 側のデフォルトが生きる（`${VAR:-}` 形式だと
  空文字がセットされてデフォルトが死ぬので注意）
- `Makefile` の trial3 系は `MPC_CONFIG_<n>` が指定された車両の compose 起動にだけ
  `MPC_CONFIG_PATH` を付与する
- 同梱プリセット `config/config_opponent_midspeed.yaml`（MPC サブモジュール側）は
  config.yaml の構造をそのまま保ったコピーで、速度プリセットのみ中高速

## 注意

- ビルドは 1 つでよい（設定差し替えのみ。第 2 worktree は不要）
- 同時に他の AWSIM セッションを走らせない（DDS 混線、CLAUDE.md Guardrails 参照）
- プリセット側の保守方針はプリセットファイル冒頭コメントを参照
  （構造的な必須キー追加時のみ同期）
