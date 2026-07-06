# 多車両戦略 FSM（CRUISE/FOLLOW/OVERTAKE）設計書

> 対象: 多車両戦略 Phase 2 の残作業のうち戦術 FSM。
> 評価フレームワーク（`docs/plan/2026-07-06-multi-vehicle-race-strategy-phase2-design.md` §4）は別セッションで独立して設計する。
> 作成日: 2026-07-06

## 1. スコープと前提

### 1.1 元設計からの変更点（本ブレストでの決定）

Phase 2 設計書（§2.1）は CRUISE/FOLLOW/OVERTAKE/DEFEND の 4 状態＋コリドーバイアス出力を
想定していたが、本設計では以下に縮小する:

- **DEFEND は Phase 2 から除外**（証拠ゲート付きで Phase 3 以降へ、§7.1）
- **コリドーバイアス出力を全廃**。FSM の出力は速度上限（speed_cap）のみ
- **`reference_path.py` への変更ゼロ**（既存 ub/lb の読み取りのみ）
- **攻撃性スカラー（§2.3）は廃止**。リスク系 3 パラメータを config 直値で持つ（§5）

縮小の根拠:

1. 全車 v_max=30km/h 同一の競技物理では、位置取り防御の期待効果が薄い
   （相手の速度優位はコーナリングライン由来で、直線 0.5m のバイアスでは消えない）
2. 衝突ペナルティ・「意図的な危険走行」の判定基準が未公表のまま、
   最もルール抵触に近い挙動を実装するのはリスク非対称
3. コリドーバイアスの実装先はコリドー絞り込みロジック
   （`core/reference_path.py`、Issue #9 の発生箇所）の真上であり、
   最も脆いコードへの増築になる
4. 追い越し能力そのものは基底層（障害物回避＋コリドー自由セグメント選択）に既にあり、
   Phase 1 実機検証で 5km/h 差のパスが成立済み。FSM に必要なのは
   「FOLLOW の速度上限をいつ外すか」の判断（＝OVERTAKE）だけ

### 1.2 前提条件（実装着手前に満たすこと）

- **`multi_purpose_mpc_ros_custom` Issue #9 の修正**（近接 2 台の相互障害物回避で
  コリドー絞り込みが破綻し片方が永久停止するバグ）。FSM 自体はコリドーに触れないが、
  実機検証（`make trial2-quick`、相互 `use_obstacle_avoidance: true`）が
  このバグに阻まれるため、別タスクとして先に修正する
- **`feat/mintime-raceline` ブランチのマージ**。speed_cap の適用点は
  このブランチが導入した v_ref の min 合成 seam（§6.1）であり、FSM はその上に積む

### 1.3 実装場所

`multi_purpose_mpc_ros_custom` サブモジュール。独立 ROS ノードではなく、
`bearing_classifier.py` / `race_state_estimator.py` と同じパターン:
rclpy 非依存の純 Python クラスを追加し、`mpc_controller.py` の制御ループ（約 40Hz）から
直接呼び出す。トピック往復の遅延なし、既存と同じ手法で単体テスト可能。

## 2. コンポーネント構成

### 2.1 新規ファイル

**`track_zone_classifier.py` — TrackZoneClassifier**

前方 lookahead 窓（コミット距離 17m 以上をカバー）のウェイポイント曲率
（既存 `Waypoint.kappa`）をしきい値判定して `STRAIGHT` / `CORNER` を返す。
ヒステリシス付き（enter/exit で異なるしきい値）。
フル版ゾーン注釈（追い越し向き区間のマップ注釈）は Phase 3 のまま。

**`race_strategy_fsm.py` — RaceStrategyFSM**

単一状態機械 `(mode, target_vehicle_id, タイマー群)` を持ち、
毎サイクル `update(inputs, dt)` で `RaceStrategyDecision` を返す。

```python
@dataclasses.dataclass
class VehicleSnapshot:            # mpc_controller.py が制御ループ内で組み立てる
    vehicle_id: str
    s: Optional[float]            # RaceStateEstimator より
    gap_m: Optional[float]        # 同上（assigned=False なら stale）
    assigned: bool
    bearing: str                  # AHEAD / BEHIND / OVERLAP
    lateral_offset_m: float       # bearing_classifier の返却拡張より（§2.2）
    speed_mps: float              # V2XVehicleTracker より

@dataclasses.dataclass
class StrategyInputs:
    ego_s: float
    ego_speed_mps: float
    zone: str                     # TrackZoneClassifier より
    vehicles: List[VehicleSnapshot]
    free_width_left_m: float      # ターゲット近傍の空き幅（§6.2）
    free_width_right_m: float

@dataclasses.dataclass
class RaceStrategyDecision:
    mode: str                     # CRUISE / FOLLOW / OVERTAKE
    target_vehicle_id: Optional[str]
    speed_cap_mps: Optional[float]  # None = 上限なし
    reason: str                   # 診断用（/strategy/mode に載せる）
```

### 2.2 既存コードへの変更

- **`bearing_classifier.py`**: `classify()` の返却をラベル文字列から
  横オフセット込みのデータクラス（label + lateral_offset_m）に拡張。
  既存呼び出し側・テストの追随修正を含む
- **`mpc_controller.py`**: フラグ・入力組み立て・speed_cap 適用・診断 publish（§6）
- **`multi_purpose_mpc_ros_custom_msgs`**: `RaceStrategyMode.msg` 追加（§6.3）
- **`reference_path.py`**: 変更なし（読み取りのみ）

## 3. 状態遷移ロジック

### 3.1 ターゲット選択（毎サイクル、遷移判定の前段）

`assigned=True` かつ `0 < gap_m ≤ d_engage_m`（既定 27m）の**最近傍の前方車**。
ただし OVERTAKE 中はコミットしたターゲットに固定し、パス途中で最近傍が
入れ替わっても再選択しない（成功/中断で抜けてから選び直す）。

### 3.2 遷移表

| 遷移 | 条件 | 即時/抑制 |
|---|---|---|
| CRUISE→FOLLOW | 前方ターゲット出現 | **即時**（上限を掛ける側は遅らせない） |
| FOLLOW→CRUISE | gap > d_engage_release_m、または stale 猶予 0.5s 超過、または前方条件喪失（gap 符号反転等） | ヒステリシス＋最小滞在 0.5s |
| FOLLOW→OVERTAKE | 全て成立: ① zone=STRAIGHT（lookahead 窓がコミット距離 17m 以上をカバー） ② 上限に実際に律速されて t_hold(1.0s) 継続 ③ いずれかの側の空き幅 ≥ W_ego+2×C_min（W_ego=`bicycle_model.width`、C_min=`overtake_min_clearance_m`） ④ クールダウン満了 ⑤ ターゲット assigned | 条件自体が時間を含む |
| OVERTAKE→CRUISE（成功） | gap 符号反転＋bearing=BEHIND が t_confirm(0.5s) 持続 | 持続確認 |
| OVERTAKE→FOLLOW（中断） | 左右どちらの空き幅も進入しきい値を下回った（成立性喪失）／**前方のどの assigned 車に対しても** TTC<ttc_abort／ターゲット assigned 喪失／zone=CORNER 到達（バックストップ）。中断後クールダウン 4s | **即時**（上限を掛け直す側） |
| コミット満了(2s)時 | 進入条件を再評価 → 成立なら再コミット、不成立なら中断扱い | — |

**原則: 制御を締める遷移（上限適用・中断）は即時、緩める遷移（上限解除・CRUISE 復帰）
だけに滞在時間・ヒステリシスを課す。** ばたつき防止と安全を両立させる非対称。

TTC 中断を「ターゲットだけでなく前方の全 assigned 車」に掛けるのは、
上限解除中に 2 台目の車が前に現れるケース（3 台走行）への備え。
基底層は横回避しかしないため、縦の安全はこの TTC チェックが最後の砦。

### 3.3 各状態の出力

- **CRUISE**: `speed_cap = None`
- **FOLLOW**: `speed_cap = max(0, (gap_m − d0) / T_gap)`（constant-time-gap 則、
  d0=2.0m 停止時マージン。gap=d0 で完全停止に収束し閉じ込みが止まる）
- **OVERTAKE**: `speed_cap = None`（解除弁を開くだけ。横の動きは基底層の
  コリドー自由セグメント選択に任せる）

### 3.4 stale（assigned=False）の扱い

- 進入判定は常に assigned=True 必須。静止車（reason=stationary）は永続的に
  未割当なので FSM は関与しない（基底層の障害物回避に任せる。Issue #9 シナリオと整合）
- FOLLOW 中に stale 化: 猶予 0.5s は直前の上限を保持 → CRUISE
- OVERTAKE 中に stale 化: 即中断

## 4. 3 台走行時の挙動

DEFEND 除外により優先規則は「最近傍の前方車」のみに単純化。
後方から接近する車には FSM は関与せず、真横まで来れば bearing=OVERLAP として
基底層が無条件で障害物化する（安全は基底層が担保）。

## 5. config パラメータ

`config.yaml` / `sim_config.yaml` に新設:

```yaml
race_strategy_fsm:
  # --- risk dial: ペナルティ規定が判明したらこの3つをセットで見直す ---
  follow_time_gap_s: 1.1          # [s] 前車への最小時間ギャップ
  overtake_ttc_abort_s: 2.5       # [s] これを切ったらパス中断
  overtake_min_clearance_m: 0.9   # [m] 進入条件の片側最小クリアランス
  # --- 構造パラメータ ---
  d_engage_m: 27.0                # [m] 前方ターゲットの検出距離
  d_engage_release_m: 32.0        # [m] FOLLOW解除のヒステリシス
  standstill_margin_m: 2.0        # [m] FOLLOW則の d0
  t_hold_s: 1.0                   # [s] 律速継続でOVERTAKE進入を許可
  t_commit_s: 2.0                 # [s] OVERTAKEコミット窓
  t_confirm_s: 0.5                # [s] 成功確認の持続時間
  cooldown_s: 4.0                 # [s] 中断後の再試行禁止
  stale_grace_s: 0.5              # [s] FOLLOW中のstale許容
  min_dwell_s: 0.5                # [s] 緩める側の遷移の最小滞在
  zone_kappa_enter: 0.08          # [1/m] これ以上でCORNER（要mintimeライン上で検証）
  zone_kappa_exit: 0.05           # [1/m] これ未満でSTRAIGHT復帰（ヒステリシス）
  zone_lookahead_m: 17.0          # [m] コミット距離をカバーする前方窓
```

攻撃性スカラーを置かない理由: 導出先が 3 つしかなく、A＋端点 6 個の 7 値で
3 値を表現する管理過剰になる。3 パラメータは本来別軸で、線形連動は根拠のない制約。
risk dial のグルーピングコメントで「当日まとめて見直す」意図は保存する。
`make optuna` でのチューニングも直値 3 つの方が素直。

## 6. `mpc_controller.py` への統合

### 6.1 speed_cap の適用点

`feat/mintime-raceline` が導入した v_ref の min 合成に第 3 項として入れる:

```python
cap = decision.speed_cap_mps  # None なら math.inf 扱い
v_ref = [min(ref_vel_kmph, vx, cap) for vx in self._traj_vx]
# traj_vx なし時も同様に min(ref_vel_kmph, cap)
```

- cap は MPC の目標値を絞る（v_ref 低下 → u[0] 低下 → `acc = KP*(u[0]−v)` が負
  → a_min=-1.6 で減速）。`update_v_max` は触らない——cap=0（gap=d0）のとき
  硬い制約 v_max=0 は QP を不安定にしかねないため、目標値経由の減速で十分
- 摩擦円クリップ（`effective_ax_limit`）は加速側上限なので干渉しない。
  OVERTAKE で cap を外せば a_max=1.0 でそのまま再加速する

### 6.2 StrategyInputs の組み立て（race_state 計算の直後）

- `ego_s` = `self._car.s`、`ego_speed` = 現在速度 v
- ゾーン = `TrackZoneClassifier.classify(wp_id)`（`self._mpc.model.wp_id` 起点の
  前方 kappa 窓。mintime ブランチの traj_ax 参照と同じパターン）
- 車両ごと: RaceState（s/gap/assigned）＋ bearing ＋ 横オフセット ＋
  速度（`V2XVehicleTracker` 保持値）
- **空き幅は静的 ub/lb ベースで自己完結**: ターゲットの wp 近傍の静的 `ub/lb` から、
  ターゲット占有帯（横オフセット ± vehicle_radius）を引いた残り幅を左右それぞれ計算。
  動的境界（障害物狭窄後）は MPC solve 内で計算されるため読み取りタイミングが絡む——
  v1 は静的＋自前減算とする。
  **しきい値の検証は mintime ライン上で行う**（width_opt=2.70 のラインは
  mincurv よりコーナーで縁に寄るため、ub/lb の残り方が変わる）

### 6.3 診断トピック `/strategy/mode`

`RaceStateArray` と同じ流儀で `multi_purpose_mpc_ros_custom_msgs` に
`RaceStrategyMode.msg` を追加:

```
string mode
string target_vehicle_id
float64 speed_cap_mps    # 上限なしのとき NaN
string reason
```

FSM 有効時に毎サイクル publish。後続の評価フレームワーク（別設計）がこれを消費する。

### 6.4 フラグ

- `use_race_strategy_fsm`（デフォルト false）
- `use_race_state_estimator` 必須（既存の依存チェーン
  「`use_race_state_estimator` は `use_obstacle_avoidance` 必須」と同じ流儀で
  起動時に検証）
- ライブパラメータコールバックにも配線（既存フラグと同様）

## 7. 除外事項と将来拡張

### 7.1 DEFEND（証拠ゲート付きで Phase 3 以降）

採用条件: trial2/trial3 の評価データで「一度のイン側バイアスがあれば守れたはずの
順位喪失」が観測され、かつ衝突ペナルティ規定が判明していること。
FSM の骨格（状態 enum ＋ Decision 構造体）はそのまま拡張可能。

### 7.2 ブースト連動

OVERTAKE ∧ zone=STRAIGHT が `boost_commander.cpp` の自然なトリガーになる
（Phase 2 設計書 §2.4）。競技合法性の確認待ち。本設計ではフックの位置だけ確保
（Decision の mode/zone を見れば外から判定できる）し、配線はしない。

## 8. テスト戦略

既存の `test_bearing_classifier.py` / `test_race_state_estimator.py` と同じ
純 Python 単体テスト:

- `TrackZoneClassifier`: 合成 kappa 列で STRAIGHT/CORNER 境界とヒステリシス
- `RaceStrategyFSM`: 遷移表の各行を 1 ケースずつ
  （即時系／滞在時間系／コミット満了の再評価／stale／クールダウン／
  OVERTAKE 中のターゲット固定）
- FOLLOW 則: gap=d0 で 0、gap 大で非拘束、の境界
- 空き幅ヘルパー: ターゲット占有帯の減算ロジック
- `bearing_classifier` 返却拡張: 既存テストの追随＋lateral_offset_m の値検証
- 実機検証: `make trial2-quick`（Issue #9 修正後）で
  FOLLOW 追従 → OVERTAKE 成立 → 成功遷移のログ（`/strategy/mode`）確認
