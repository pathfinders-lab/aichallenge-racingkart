# Standstill デッドロック対策（予防＋保険）設計

対象リポジトリ: `multi_purpose_mpc_ros_custom`（本書は経緯・設計の記録として本体リポジトリに置く）
チケット: 予防=pathfinders-lab/multi_purpose_mpc_ros_custom#33、保険=pathfinders-lab/multi_purpose_mpc_ros_custom#31（機序の実測は本体 #43 / #50 のコメント参照）
関連 bag: `output/20260707-111842`（本体リポジトリのメインチェックアウトに保全済み）

## 1. 背景と問題

trial2 の速度差シナリオで確定再現したデッドロックの機序（本体 #43）:

1. 後続車が遅い先行車に接近すると、狭い区間で QP が間欠的に infeasible になる
   （10s バケットで 10〜18%。走行中の慢性 infeasible ではない — 初期解析の誤りを訂正済み）
2. infeasible 周期は**最後に解けた計画を盲目再生**するため、相手が動いた後の空間へ
   突っ込み、接触級接近（min 0.27m）が発生する【予防で潰す対象】
3. すれ違いかけで両車の FSM が相互に FOLLOW cap=0 を発動（お見合い）し停止
4. 停止後は相手の V2X 障害物がコリドーを塞ぎ **QP が 100% infeasible で永続**。
   再生プールを使い切ると u=[0,0] を出し続け、**回復経路のない吸収状態**になる
   【保険で潰す対象】

本番レースは自チーム 1 台＋他チームのため、3 の「お見合い」はテスト環境固有の
アーティファクト（本番の相手は譲らない）。本番で現実に起きるのは
「遅い/停止した相手の後ろで詰まって固まる」の片側であり、2 と 4 が本番リスク。

## 2. スコープ

- **Fix-1（予防、multi_purpose_mpc_ros_custom#33）**: infeasible 再生時の減速オーバーレイ＋ solved 判定バグ修正
- **Fix-2（保険、multi_purpose_mpc_ros_custom#31）**: standstill 回復スーパーバイザ（徐行脱出）
- 実装は独立した 2 PR（Fix-1 → Fix-2 の順。Fix-2 のテストは修正済み solved 判定を前提にする）

### スコープ外（理由つき）

- **お見合い tie-break**（相互 FOLLOW の同時譲り防止）: テスト環境固有。必要になれば
  FSM のターゲット選択に s 順の譲り優先度を入れる別チケット
- **overtake_min_clearance_m の見直し**: 本体 #50 で実効コリドー幅の分布から別途
- **戦略層 STUCK 状態（後退・譲り）**: Phase 3（本体 #50 完了条件の後続判断）

## 3. Fix-1: infeasible 再生の減速オーバーレイ（multi_purpose_mpc_ros_custom#33）

### 3.1 変更点（`core/MPC.py` のみ）

1. **solved 判定バグ修正**: `solved = control_signals is not None and np.all(control_signals[1::2])`
   の `np.all(...)` 条件を削除する（ladder 内の同型判定も同様）。
   `extract_controls` が None / NaN を検査済みであり、「全ステア値が非ゼロ」という
   条件は停止・直進の正当解を infeasible と誤判定する。
2. **減速オーバーレイ**: 例外パス（再生時）で、ステアは計画値のまま、速度のみ

   ```
   v_cmd = max(0.0, planned_v − infeasible_brake_decel × Ts × infeasibility_counter)
   ```

   `infeasible_brake_decel` はコンストラクタ引数（デフォルト 2.0 m/s²）。
   再生プール枯渇時の u=[0,0] フォールバックは現状維持。

### 3.2 性質

- 単発〜数周期の infeasible では減衰量 ≈ 0（既存挙動を保つ。counter=5, Ts=0.025 で −0.25 m/s）
- infeasible が続くほど強く減速し、盲目走行の運動エネルギーを奪う
  （1 秒継続で −2 m/s。controller 側の `acc = KP·(u[0]−v)` と a_min クリップが実際の減速を律速）
- `compute_v_max_fallback_factor`（counter≥3/≥5 で次回の解の v_max を絞る既存機構）とは
  相補: fallback は「次に解けた後」、本オーバーレイは「解けていない間」に効く

### 3.3 config

`mpc:` セクションに `infeasible_brake_decel: 2.0  # m/s^2` を追加し、
controller が MPC コンストラクタへ渡す。

## 4. Fix-2: standstill 回復スーパーバイザ（multi_purpose_mpc_ros_custom#31）

### 4.1 コンポーネント

`standstill_recovery.py`（新規、rclpy-free 純クラス。bearing_classifier 等と同パターン）:

```python
RECOVERY_INACTIVE = "inactive"
RECOVERY_ACTIVE = "active"

@dataclass
class StandstillRecoveryConfig:
    trigger_stopped_speed_mps: float = 0.5   # これ未満で「停止」
    trigger_duration_s: float = 2.0          # 停止×infeasible がこれだけ連続で突入
    creep_speed_mps: float = 1.5             # 回復中の徐行上限
    exit_distance_m: float = 5.0             # 突入地点からの走行距離で復帰
    exit_duration_s: float = 10.0            # または経過時間で復帰

@dataclass
class RecoveryDecision:
    active: bool
    creep_cap_mps: Optional[float]   # active 時のみ creep_speed_mps
    reason: str                      # "inactive" | "triggered" | "recovering" | "exit_distance" | "exit_timeout"

class StandstillRecovery:
    def update(self, ego_speed_mps: float, is_feasible: bool,
               traveled_m: float, dt: float) -> RecoveryDecision
```

`traveled_m` は controller が積算して渡す（`ego_speed × dt` の累積。回復突入時に
クラス内部で基準リセット）。

### 4.2 controller 結線（`mpc_controller.py`）

- フラグ `use_standstill_recovery`（デフォルト false、co-req: `use_obstacle_avoidance`。
  FSM フラグと同じ流儀で宣言・ログ・live param 対応）
- `_control()` で毎周期 `update(ego_speed, solve_stats.is_feasible, traveled, dt)`
- **active 中の 3 作用**:
  1. 動的（V2X）障害物をマップ投入から除外（`add_obstacles(static + dynamic)` seam で
     dynamic を落とす。静的壁は維持。除外/復帰時は `_obstacles_updated` を立てて再構築）
  2. v_ref 再焼き込みキャップに `creep_cap_mps` を適用（FSM cap と同じ seam）
  3. **FSM speed_cap はサスペンド**（回復は戦略より優先される安全層。
     effective_cap = recovery active ? creep_cap : strategy_cap）
- 診断: `/strategy/recovery`（新 msg `StandstillRecoveryState`: `bool active` /
  `string reason` / `float64 elapsed_s`）を publish。遷移時に logger.warn

### 4.3 出口と再突入

突入地点から `exit_distance_m` 走行、または `exit_duration_s` 経過で INACTIVE へ復帰
（障害物投入・FSM cap 復活）。復帰後もまだ詰まっていれば `trigger_duration_s` 後に
再突入する（自然なリトライループ。追加の状態は持たない）。

### 4.4 既知のトレードオフ

- 回復中は相手車を計算から外すため、**相手が完全に線上に静止している場合は
  徐行で接近し得る**（1.5 m/s）。相互ケースでは双方が動き出すため解消する。
  片側ケース（停止 NPC 等）での接触リスクは徐行速度で緩和し、live 検証で評価する
- Fix-1 の減速オーバーレイは回復中も有効（infeasible なら徐行からさらに減速）

## 5. テスト計画

- **Fix-1 ユニット**: 減衰式（counter 単調増で v_cmd 単調減 / counter 小で既存同等 /
  下限 0 クリップ）、ゼロステア解が solved になる回帰
- **Fix-2 ユニット**: 突入（2 条件×継続時間）/ 非突入（片条件のみ・断続）/
  出口（距離・時間それぞれ）/ 再突入ループ / reason 遷移
- **default-off parity**: 両フラグ off で runtime 挙動が現行と一致（FSM PR と同じ観点）
- **live（本体 #50 シナリオ再走**、launch 一時 ON）:
  - 接触級接近（min_dist < 1.0m）が消える（Fix-1）
  - 詰まってもタイムアウトせず追走が継続する（Fix-2）
  - 単独走行・通常 trial に回帰なし

## 6. 実装順

1. Fix-1（multi_purpose_mpc_ros_custom#33、PR 1 本目）: core/MPC.py＋config＋テスト
2. Fix-2（multi_purpose_mpc_ros_custom#31、PR 2 本目）: standstill_recovery.py＋msg＋controller 結線＋config＋テスト
3. 親リポジトリ: submodule bump＋launch フラグ配線＋live 検証（#50 で記録）
