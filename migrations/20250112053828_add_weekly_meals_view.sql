CREATE VIEW weekly_meals_view AS
WITH RECURSIVE dates AS (
  -- Get the earliest and latest dates
  SELECT
    DATE_TRUNC('week', MIN(created_at)) AS week_start,
    DATE_TRUNC('week', MAX(created_at)) AS latest_week
  FROM meals
  
  UNION ALL
  
  SELECT 
    week_start + INTERVAL '1 week',
    latest_week
  FROM dates
  WHERE week_start + INTERVAL '1 week' <= latest_week
),
daily_totals AS (
  SELECT
    user_id,
    DATE_TRUNC('day', created_at) AS day,
    SUM(protein_amount) as daily_protein
  FROM meals
  GROUP BY user_id, DATE_TRUNC('day', created_at)
)
SELECT
  m.user_id,
  d.week_start,
  d.week_start + INTERVAL '6 days' AS week_end,
  COALESCE(SUM(dt.daily_protein), 0) as total_protein,
  COUNT(DISTINCT DATE_TRUNC('day', dt.day)) as days_logged,
  ARRAY_AGG(
    json_build_object(
      'date', dt.day,
      'protein', dt.daily_protein
    )
    ORDER BY dt.day
  ) as daily_breakdown
FROM dates d
CROSS JOIN (SELECT DISTINCT user_id FROM meals) m
LEFT JOIN daily_totals dt 
  ON dt.user_id = m.user_id 
  AND dt.day >= d.week_start 
  AND dt.day < d.week_start + INTERVAL '7 days'
GROUP BY m.user_id, d.week_start
ORDER BY d.week_start DESC;
