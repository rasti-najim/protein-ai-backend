CREATE OR REPLACE FUNCTION update_streaks()
RETURNS void
LANGUAGE plpgsql
AS $$
DECLARE
  target_timezone TEXT := 'UTC';
BEGIN
  -- Only process users who have meals today that haven't been processed
  WITH daily_totals AS (
    SELECT
      m.user_id,
      DATE(m.created_at AT TIME ZONE target_timezone) as meal_date,
      COALESCE(SUM(m.protein_amount), 0) AS total_protein,
      u.daily_protein_target
    FROM meals m
    JOIN users u ON u.id = m.user_id
    WHERE 
      -- Only look at today's meals
      DATE(m.created_at AT TIME ZONE target_timezone) = CURRENT_DATE AT TIME ZONE target_timezone
      -- Only process meals from the last minute
      AND m.created_at >= NOW() - INTERVAL '1 minute'
    GROUP BY m.user_id, DATE(m.created_at AT TIME ZONE target_timezone), u.daily_protein_target
  )
  UPDATE streaks us
  SET
    current_streak = CASE
      WHEN dt.total_protein >= dt.daily_protein_target
        AND us.updated_at = CURRENT_DATE - 1
      THEN us.current_streak + 1
      WHEN dt.total_protein >= dt.daily_protein_target
      THEN 1
      ELSE us.current_streak
    END,
    updated_at = CASE
      WHEN dt.total_protein >= dt.daily_protein_target
      THEN CURRENT_DATE
      ELSE us.updated_at
    END,
    max_streak = GREATEST(
      us.max_streak,
      CASE
        WHEN dt.total_protein >= dt.daily_protein_target
          AND us.updated_at = CURRENT_DATE - 1
        THEN us.current_streak + 1
        WHEN dt.total_protein >= dt.daily_protein_target
        THEN 1
        ELSE us.max_streak
      END
    )
  FROM daily_totals dt
  WHERE us.user_id = dt.user_id;

EXCEPTION 
  WHEN OTHERS THEN
    RAISE NOTICE 'Error updating streaks: %', SQLERRM;
    RETURN;
END;
$$;