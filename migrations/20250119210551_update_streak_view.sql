-- Drop the view first since it depends on the streaks table
DROP VIEW IF EXISTS user_streak_view;

-- Now we can safely drop the streaks table
DROP TABLE IF EXISTS streaks;

-- Create the new view that calculates streaks directly from meals
CREATE OR REPLACE VIEW user_streak_view AS
WITH daily_totals AS (
  SELECT 
    m.user_id,
    DATE(m.created_at) as date,
    SUM(m.protein_amount) as total_protein,
    u.daily_protein_target
  FROM meals m
  JOIN users u ON u.id = m.user_id
  GROUP BY m.user_id, DATE(m.created_at), u.daily_protein_target
),
streak_calc AS (
  SELECT 
    user_id,
    date,
    CASE 
      WHEN total_protein >= daily_protein_target THEN 1
      ELSE 0
    END as goal_met,
    COUNT(*) FILTER (WHERE total_protein >= daily_protein_target) 
      OVER (PARTITION BY user_id ORDER BY date) as current_streak
  FROM daily_totals
  WHERE date < CURRENT_DATE  -- Only count completed days
)
SELECT 
  dt.user_id,
  COALESCE(MAX(sc.current_streak), 0) as current_streak,
  COALESCE(MAX(sc.current_streak), 0) as max_streak,
  (
    SELECT sl.name
    FROM streak_levels sl
    WHERE sl.threshold <= COALESCE(MAX(sc.current_streak), 0)
    ORDER BY sl.threshold DESC
    LIMIT 1
  ) as streak_name,
  (
    SELECT sl.emoji
    FROM streak_levels sl
    WHERE sl.threshold <= COALESCE(MAX(sc.current_streak), 0)
    ORDER BY sl.threshold DESC
    LIMIT 1
  ) as streak_emoji,
  (
    SELECT MIN(sl.threshold - COALESCE(MAX(sc.current_streak), 0))
    FROM streak_levels sl
    WHERE sl.threshold > COALESCE(MAX(sc.current_streak), 0)
  ) as days_to_next_level
FROM daily_totals dt
LEFT JOIN streak_calc sc ON sc.user_id = dt.user_id
GROUP BY dt.user_id;

-- Add helpful index for performance
CREATE INDEX IF NOT EXISTS idx_meals_user_date ON meals(user_id, created_at);