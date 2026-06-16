# Design: multi_purpose_mpc_ros_custom パッケージ作成

Date: 2026-06-17

## 概要

`multi_purpose_mpc_ros` を完全コピーして `multi_purpose_mpc_ros_custom` を作成する。
オリジナルはリファレンスとして残し、カスタム版で実験・改造を行う。
カスタム版は将来的に別リポジトリとして切り出す予定のため、今回は plain copy のみ行う。

## 変更範囲

### 新規パッケージ: `multi_purpose_mpc_ros_custom`

場所: `aichallenge/workspace/src/aichallenge_submit/multi_purpose_mpc_ros_custom/`

**手順:**

1. **ディレクトリコピー**
   ```
   cp -r multi_purpose_mpc_ros multi_purpose_mpc_ros_custom
   ```

2. **Python モジュールディレクトリのリネーム**
   ```
   multi_purpose_mpc_ros_custom/multi_purpose_mpc_ros/
     → multi_purpose_mpc_ros_custom/multi_purpose_mpc_ros_custom/
   ```

3. **文字列一括置換（新パッケージ内）**
   - `multi_purpose_mpc_ros_msgs` は保持（依存する別パッケージのため変更しない）
   - `multi_purpose_mpc_ros` → `multi_purpose_mpc_ros_custom` に置換
   - 対象ファイル: `.py`, `.cpp`, `.hpp`, `.xml`, `.yaml`, `.bash`, `.txt`, `.md`, 実行スクリプト
   - 除外: バイナリファイル (`.pgm`, `.pdf`, `.png` 等)

4. **置換対象となる主要ファイル**
   - `package.xml`: `<name>` タグ
   - `CMakeLists.txt`: `project()`, `ament_python_install_package()`, `install(PROGRAMS ... DESTINATION)` 等
   - `multi_purpose_mpc_ros_custom/*.py`: Python import 文
   - `multi_purpose_mpc_ros_custom/core/*.py`: Python import 文
   - `multi_purpose_mpc_ros_custom/tools/*.py`: Python import 文
   - `launch/*.py`: `package` 引数
   - `scripts/*`: shebang や import 文

### 既存ファイル変更: `aichallenge_submit_launch`

`launch/control/mpc.launch.xml`:
- `pkg="multi_purpose_mpc_ros"` → `pkg="multi_purpose_mpc_ros_custom"`
- `$(find-pkg-share multi_purpose_mpc_ros)` → `$(find-pkg-share multi_purpose_mpc_ros_custom)`

## 制約

- `multi_purpose_mpc_ros` (オリジナル) は削除しない
- `multi_purpose_mpc_ros_msgs` はリネームしない
- git submodule 設定は今回のスコープ外

## 検証

- `colcon build --packages-select multi_purpose_mpc_ros_custom` でビルドが通ること
- `ros2 launch aichallenge_submit_launch mpc.launch.xml` が custom パッケージを参照すること
