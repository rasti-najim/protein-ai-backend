CREATE OR REPLACE FUNCTION update_streaks()
RETURNS void
LANGUAGE plpgsql
AS $$
DECLARE
  target_timezone TEXT := 'UTC'; -- or configure as needed
BEGIN
  WITH daily_totals AS (
    SELECT
      m.user_id,
      COALESCE(SUM(m.protein), 0) AS total_protein
    FROM meals m
    WHERE DATE(m.created_at AT TIME ZONE target_timezone) = CURRENT_DATE AT TIME ZONE target_timezone
    GROUP BY m.user_id
  )
  UPDATE streaks us
  SET
    current_streak = CASE
      WHEN COALESCE(dt.total_protein, 0) >= COALESCE(u.daily_target, 0)
        AND us.last_streak_date = CURRENT_DATE - 1
      THEN us.current_streak + 1
      WHEN COALESCE(dt.total_protein, 0) >= COALESCE(u.daily_target, 0)
      THEN 1
      ELSE 0
    END,
    last_streak_date = CASE
      WHEN COALESCE(dt.total_protein, 0) >= COALESCE(u.daily_target, 0)
      THEN CURRENT_DATE
      ELSE us.last_streak_date
    END,
    max_streak = GREATEST(
      us.max_streak,
      CASE
        WHEN COALESCE(dt.total_protein, 0) >= COALESCE(u.daily_target, 0)
          AND us.last_streak_date = CURRENT_DATE - 1
        THEN us.current_streak + 1
        WHEN COALESCE(dt.total_protein, 0) >= COALESCE(u.daily_target, 0)
        THEN 1
        ELSE us.max_streak
      END
    )
  FROM users u
  LEFT JOIN daily_totals dt ON dt.user_id = u.id
  WHERE us.user_id = u.id;

EXCEPTION 
  WHEN OTHERS THEN
    -- Log error or handle as needed
    RAISE NOTICE 'Error updating streaks: %', SQLERRM;
    RETURN;
END;
$$;

-- Add helpful indexes
CREATE INDEX IF NOT EXISTS idx_meals_user_date ON meals(user_id, meal_date);
CREATE INDEX IF NOT EXISTS idx_user_streaks_user ON user_streaks(user_id);
