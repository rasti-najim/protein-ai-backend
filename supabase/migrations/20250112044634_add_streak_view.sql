ALTER TABLE streaks DROP COLUMN streak_level_id;

CREATE VIEW user_streak_view AS
SELECT
  us.user_id,
  us.current_streak,
  us.max_streak,
  (
    SELECT sl.name
    FROM streak_levels sl
    WHERE sl.threshold <= us.current_streak
    ORDER BY sl.threshold DESC
    LIMIT 1
  ) AS streak_name,
  (
    SELECT sl.emoji
    FROM streak_levels sl
    WHERE sl.threshold <= us.current_streak
    ORDER BY sl.threshold DESC
    LIMIT 1
  ) AS streak_emoji
FROM streaks us;
