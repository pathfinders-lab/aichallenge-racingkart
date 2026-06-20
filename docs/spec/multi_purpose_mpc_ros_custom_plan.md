# multi_purpose_mpc_ros_custom Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** `multi_purpose_mpc_ros` を完全コピーして `multi_purpose_mpc_ros_custom` を作成し、`aichallenge_submit_launch` の launch を新パッケージに切り替える。

**Architecture:** ディレクトリを丸ごとコピーし、Python モジュールディレクトリのリネームと全テキストファイルの文字列置換でパッケージ名を変更する。`multi_purpose_mpc_ros_msgs` は別パッケージのため変更しない。

**Tech Stack:** ROS2 Humble, Python 3, CMake (ament_cmake), bash, sed

---

## File Map

**新規作成 (コピー元から生成):**
- `aichallenge/workspace/src/aichallenge_submit/multi_purpose_mpc_ros_custom/` — 新パッケージルート

**変更 (新パッケージ内・コピー後に置換):**
- `multi_purpose_mpc_ros_custom/package.xml`
- `multi_purpose_mpc_ros_custom/CMakeLists.txt`
- `multi_purpose_mpc_ros_custom/multi_purpose_mpc_ros_custom/*.py` (Python module dir rename 後)
- `multi_purpose_mpc_ros_custom/multi_purpose_mpc_ros_custom/core/*.py`
- `multi_purpose_mpc_ros_custom/multi_purpose_mpc_ros_custom/tools/*.py`
- `multi_purpose_mpc_ros_custom/launch/*.py`
- `multi_purpose_mpc_ros_custom/scripts/*`

**変更 (既存パッケージ):**
- `aichallenge/workspace/src/aichallenge_submit/aichallenge_submit_launch/launch/control/mpc.launch.xml`

---

### Task 1: パッケージディレクトリをコピーする

**Files:**
- Create: `aichallenge/workspace/src/aichallenge_submit/multi_purpose_mpc_ros_custom/`

- [ ] **Step 1: コピー実行**

```bash
cd aichallenge/workspace/src/aichallenge_submit
cp -r multi_purpose_mpc_ros multi_purpose_mpc_ros_custom
```

- [ ] **Step 2: ファイル数を確認してコピーが完全であることを確認**

```bash
orig=$(find multi_purpose_mpc_ros -type f | wc -l)
copy=$(find multi_purpose_mpc_ros_custom -type f | wc -l)
echo "original: $orig, copy: $copy"
```

Expected: 両方の数値が一致すること（例: `original: 67, copy: 67`）

- [ ] **Step 3: Python モジュールディレクトリをリネーム**

```bash
mv multi_purpose_mpc_ros_custom/multi_purpose_mpc_ros \
   multi_purpose_mpc_ros_custom/multi_purpose_mpc_ros_custom
```

- [ ] **Step 4: リネームを確認**

```bash
ls multi_purpose_mpc_ros_custom/
```

Expected: `multi_purpose_mpc_ros_custom/` ディレクトリが存在し、`multi_purpose_mpc_ros/` は存在しないこと

---

### Task 2: 新パッケージ内の文字列を一括置換する

`multi_purpose_mpc_ros` を `multi_purpose_mpc_ros_custom` に置換する。
ただし `multi_purpose_mpc_ros_msgs` は別パッケージのため変更しない。

**Files:**
- Modify: `multi_purpose_mpc_ros_custom/` 以下の全テキストファイル

- [ ] **Step 1: 置換スクリプトを実行**

3パス sed で `_msgs` を守りながら置換する:

```bash
cd aichallenge/workspace/src/aichallenge_submit
find multi_purpose_mpc_ros_custom -type f \
  ! -name "*.pgm" ! -name "*.png" ! -name "*.pdf" ! -name "*.csv" \
  -exec sed -i \
    -e 's/multi_purpose_mpc_ros_msgs/__MSGS_PLACEHOLDER__/g' \
    -e 's/multi_purpose_mpc_ros/multi_purpose_mpc_ros_custom/g' \
    -e 's/__MSGS_PLACEHOLDER__/multi_purpose_mpc_ros_msgs/g' \
    {} +
```

- [ ] **Step 2: 置換漏れがないか確認（`_msgs` を除いて `multi_purpose_mpc_ros_custom` 以外が残っていないこと）**

```bash
grep -r "multi_purpose_mpc_ros" multi_purpose_mpc_ros_custom \
  --include="*.py" --include="*.cpp" --include="*.hpp" \
  --include="*.xml" --include="*.yaml" --include="*.bash" \
  --include="*.txt" --include="*.md" \
  | grep -v "multi_purpose_mpc_ros_custom" \
  | grep -v "multi_purpose_mpc_ros_msgs"
```

Expected: 出力が空であること（何も表示されない）

- [ ] **Step 3: `_msgs` が壊れていないか確認**

```bash
grep -r "multi_purpose_mpc_ros_msgs" multi_purpose_mpc_ros_custom \
  --include="*.py" --include="*.xml"
```

Expected: `package.xml` 等に `multi_purpose_mpc_ros_msgs` がそのまま残っていること

- [ ] **Step 4: `package.xml` の `<name>` タグを確認**

```bash
grep "<name>" multi_purpose_mpc_ros_custom/package.xml
```

Expected: `<name>multi_purpose_mpc_ros_custom</name>`

- [ ] **Step 5: CMakeLists.txt の `project()` を確認**

```bash
grep "^project(" multi_purpose_mpc_ros_custom/CMakeLists.txt
```

Expected: `project(multi_purpose_mpc_ros_custom)`

---

### Task 3: `aichallenge_submit_launch` の launch ファイルを更新する

**Files:**
- Modify: `aichallenge_submit_launch/launch/control/mpc.launch.xml`

- [ ] **Step 1: 変更前の内容を確認**

```bash
cat aichallenge/workspace/src/aichallenge_submit/aichallenge_submit_launch/launch/control/mpc.launch.xml
```

- [ ] **Step 2: `pkg` と `find-pkg-share` の参照を `multi_purpose_mpc_ros_custom` に更新**

`aichallenge/workspace/src/aichallenge_submit/aichallenge_submit_launch/launch/control/mpc.launch.xml` を以下に書き換える:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<launch>
  <arg name="use_sim_time" default="true"/>
  <arg name="use_obstacle_avoidance" default="false"/>

  <node pkg="multi_purpose_mpc_ros_custom" exec="run_mpc_controller.bash"
        name="mpc_controller" output="screen"
        args="--config_path $(find-pkg-share multi_purpose_mpc_ros_custom)/config/config.yaml
              --ref_vel_path $(find-pkg-share multi_purpose_mpc_ros_custom)/config/ref_vel.yaml">
    <param name="use_sim_time" value="$(var use_sim_time)"/>
    <param name="use_boost_acceleration" value="false"/>
    <param name="use_obstacle_avoidance" value="$(var use_obstacle_avoidance)"/>
    <param name="use_stats" value="false"/>
  </node>
</launch>
```

- [ ] **Step 3: 変更後の内容を確認**

```bash
grep "multi_purpose_mpc_ros" aichallenge/workspace/src/aichallenge_submit/aichallenge_submit_launch/launch/control/mpc.launch.xml
```

Expected: `multi_purpose_mpc_ros_custom` のみが表示され、`multi_purpose_mpc_ros"` (custom なし) は表示されないこと

---

### Task 4: ビルドして動作確認する

- [ ] **Step 1: 新パッケージをビルド**

```bash
cd aichallenge/workspace
colcon build --packages-select multi_purpose_mpc_ros_custom
```

Expected: `Summary: 1 package finished` と表示されビルドが成功すること

- [ ] **Step 2: `aichallenge_submit_launch` もビルド**

```bash
colcon build --packages-select aichallenge_submit_launch
```

Expected: `Summary: 1 package finished`

- [ ] **Step 3: パッケージが ROS2 に認識されているか確認**

```bash
source install/setup.bash
ros2 pkg list | grep multi_purpose_mpc_ros
```

Expected:
```
multi_purpose_mpc_ros
multi_purpose_mpc_ros_custom
multi_purpose_mpc_ros_msgs
```

---

### Task 5: コミットする

- [ ] **Step 1: pre-commit チェックを通す**

```bash
cd /home/es-165/aichallenge-racingkart
pre-commit run -a
```

Expected: 全チェックが PASSED または auto-fix されること。失敗した場合は修正して再実行する。

- [ ] **Step 2: 変更ファイルを確認**

```bash
git status
```

Expected: `multi_purpose_mpc_ros_custom/` の新規ファイル群と `mpc.launch.xml` の変更が表示されること

- [ ] **Step 3: コミット**

```bash
git add aichallenge/workspace/src/aichallenge_submit/multi_purpose_mpc_ros_custom/
git add aichallenge/workspace/src/aichallenge_submit/aichallenge_submit_launch/launch/control/mpc.launch.xml
git commit -m "feat: add multi_purpose_mpc_ros_custom package copied from multi_purpose_mpc_ros"
```
