float64 solve_time_ms        # total solver time including retries [ms]
int32   infeasible_count     # consecutive infeasible steps (0 when solved)
bool    is_feasible          # true if solved this step
int32   relaxed_margin_level # 0=no relaxation, 1-5=level, -1=infeasible
int32   wp_id                # current waypoint index
int32   n_horizon            # horizon length N used in this solve
