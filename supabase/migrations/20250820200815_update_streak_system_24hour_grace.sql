-- Update streak system to use 24-hour rolling window with 4-hour grace period

-- Add columns to track streak periods more precisely
ALTER TABLE user_streaks 
ADD COLUMN last_goal_timestamp TIMESTAMP WITH TIME ZONE,
ADD COLUMN grace_period_hours INTEGER DEFAULT 4;

-- Update daily_protein_totals to track 24-hour periods
ALTER TABLE daily_protein_totals
ADD COLUMN period_start TIMESTAMP WITH TIME ZONE,
ADD COLUMN period_end TIMESTAMP WITH TIME ZONE;

-- Create index for timestamp-based queries
CREATE INDEX idx_user_streaks_last_goal_timestamp ON user_streaks (user_id, last_goal_timestamp);

-- Updated function to handle 24-hour rolling window with grace period
CREATE OR REPLACE FUNCTION update_user_streak(target_user_id UUID)
RETURNS TABLE (
  current_streak INTEGER,
  max_streak INTEGER,
  streak_extended BOOLEAN,
  goal_met_today BOOLEAN
) AS $$
DECLARE
  user_timezone TEXT;
  user_target INTEGER;
  now_time TIMESTAMP WITH TIME ZONE;
  last_24h_start TIMESTAMP WITH TIME ZONE;
  last_goal_time TIMESTAMP WITH TIME ZONE;
  grace_period_hours INTEGER := 4;
  total_protein_24h INTEGER;
  current_streak_val INTEGER := 0;
  max_streak_val INTEGER := 0;
  streak_extended_val BOOLEAN := FALSE;
  goal_met_today_val BOOLEAN := FALSE;
  streak_should_continue BOOLEAN := FALSE;
BEGIN
  -- Get user timezone, target, and current streak info
  SELECT 
    COALESCE(au.user_metadata->>'timezone', 'UTC'),
    u.daily_protein_target,
    COALESCE(us.current_streak, 0),
    COALESCE(us.max_streak, 0),
    us.last_goal_timestamp
  INTO user_timezone, user_target, current_streak_val, max_streak_val, last_goal_time
  FROM auth.users au
  JOIN users u ON u.id = au.id
  LEFT JOIN user_streaks us ON us.user_id = u.id
  WHERE u.id = target_user_id;

  -- Calculate current time in user's timezone
  now_time := NOW() AT TIME ZONE user_timezone;
  last_24h_start := now_time - INTERVAL '24 hours';

  -- Get total protein in the last 24 hours
  SELECT COALESCE(SUM(protein_amount), 0)
  INTO total_protein_24h
  FROM meals
  WHERE user_id = target_user_id
    AND created_at AT TIME ZONE user_timezone >= last_24h_start
    AND created_at AT TIME ZONE user_timezone <= now_time;

  -- Check if goal is met in the last 24 hours
  goal_met_today_val := total_protein_24h >= user_target;

  -- Update daily totals cache for the current 24-hour period
  INSERT INTO daily_protein_totals (user_id, date, total_protein, goal_met, period_start, period_end)
  VALUES (
    target_user_id, 
    DATE(now_time), 
    total_protein_24h, 
    goal_met_today_val,
    last_24h_start,
    now_time
  )
  ON CONFLICT (user_id, date) 
  DO UPDATE SET 
    total_protein = total_protein_24h,
    goal_met = goal_met_today_val,
    period_start = last_24h_start,
    period_end = now_time,
    updated_at = CURRENT_TIMESTAMP;

  -- Calculate streak logic with 24-hour window and grace period
  IF goal_met_today_val THEN
    -- Check if we should continue the streak (within grace period)
    IF last_goal_time IS NOT NULL THEN
      -- Calculate time since last goal achievement
      streak_should_continue := (
        now_time - last_goal_time <= INTERVAL '24 hours' + (grace_period_hours || ' hours')::INTERVAL
      );
      
      IF streak_should_continue THEN
        -- Continue/extend existing streak
        current_streak_val := current_streak_val + 1;
        streak_extended_val := TRUE;
      ELSE
        -- Start new streak (grace period exceeded)
        current_streak_val := 1;
        streak_extended_val := FALSE;
      END IF;
    ELSE
      -- First time achieving goal (new user)
      current_streak_val := 1;
      streak_extended_val := FALSE;
    END IF;
    
    -- Update max streak if needed
    max_streak_val := GREATEST(max_streak_val, current_streak_val);
    
    -- Set last goal timestamp to now
    last_goal_time := now_time;
  ELSE
    -- Goal not met, check if we're still within grace period
    IF last_goal_time IS NOT NULL AND 
       (now_time - last_goal_time <= (grace_period_hours || ' hours')::INTERVAL) THEN
      -- Still within grace period, don't break streak
      streak_extended_val := FALSE;
    ELSE
      -- Grace period exceeded or no previous goal, check if streak should be broken
      IF last_goal_time IS NOT NULL AND 
         (now_time - last_goal_time > INTERVAL '24 hours' + (grace_period_hours || ' hours')::INTERVAL) THEN
        -- Break the streak
        current_streak_val := 0;
      END IF;
      streak_extended_val := FALSE;
    END IF;
  END IF;

  -- Insert or update user streak
  INSERT INTO user_streaks (
    user_id, 
    current_streak, 
    max_streak, 
    last_goal_date,
    last_goal_timestamp,
    grace_period_hours
  )
  VALUES (
    target_user_id, 
    current_streak_val, 
    max_streak_val, 
    CASE WHEN goal_met_today_val THEN DATE(now_time) ELSE NULL END,
    CASE WHEN goal_met_today_val THEN now_time ELSE last_goal_time END,
    grace_period_hours
  )
  ON CONFLICT (user_id)
  DO UPDATE SET
    current_streak = current_streak_val,
    max_streak = max_streak_val,
    last_goal_date = CASE WHEN goal_met_today_val THEN DATE(now_time) ELSE user_streaks.last_goal_date END,
    last_goal_timestamp = CASE WHEN goal_met_today_val THEN now_time ELSE user_streaks.last_goal_timestamp END,
    grace_period_hours = grace_period_hours,
    updated_at = CURRENT_TIMESTAMP;

  -- Return results
  RETURN QUERY SELECT 
    current_streak_val,
    max_streak_val,
    streak_extended_val,
    goal_met_today_val;
END;
$$ LANGUAGE plpgsql;