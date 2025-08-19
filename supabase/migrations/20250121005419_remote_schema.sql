create or replace view "public"."user_streak_view" as  WITH daily_totals AS (
         SELECT m.user_id,
            date(m.created_at) AS date,
            sum(m.protein_amount) AS total_protein,
            u.daily_protein_target
           FROM (meals m
             JOIN users u ON ((u.id = m.user_id)))
          GROUP BY m.user_id, (date(m.created_at)), u.daily_protein_target
        ), streak_calc AS (
         SELECT daily_totals.user_id,
            daily_totals.date,
                CASE
                    WHEN (daily_totals.total_protein >= daily_totals.daily_protein_target) THEN 1
                    ELSE 0
                END AS goal_met,
            count(*) FILTER (WHERE (daily_totals.total_protein >= daily_totals.daily_protein_target)) OVER (PARTITION BY daily_totals.user_id ORDER BY daily_totals.date) AS current_streak
           FROM daily_totals
        )
 SELECT dt.user_id,
    COALESCE(max(sc.current_streak) FILTER (WHERE (sc.date = CURRENT_DATE)), (0)::bigint) AS current_streak,
    COALESCE(max(sc.current_streak), (0)::bigint) AS max_streak,
    ( SELECT sl.name
           FROM streak_levels sl
          WHERE (sl.threshold <= COALESCE(max(sc.current_streak), (0)::bigint))
          ORDER BY sl.threshold DESC
         LIMIT 1) AS streak_name,
    ( SELECT sl.emoji
           FROM streak_levels sl
          WHERE (sl.threshold <= COALESCE(max(sc.current_streak), (0)::bigint))
          ORDER BY sl.threshold DESC
         LIMIT 1) AS streak_emoji,
    ( SELECT min((sl.threshold - COALESCE(max(sc.current_streak), (0)::bigint))) AS min
           FROM streak_levels sl
          WHERE (sl.threshold > COALESCE(max(sc.current_streak), (0)::bigint))) AS days_to_next_level
   FROM (daily_totals dt
     LEFT JOIN streak_calc sc ON ((sc.user_id = dt.user_id)))
  GROUP BY dt.user_id;



