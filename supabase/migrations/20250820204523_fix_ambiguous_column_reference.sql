-- Fix ambiguous column reference in update_user_streak function

CREATE OR REPLACE FUNCTION update_user_streak(target_user_id UUID)
RETURNS TABLE (
  current_streak INTEGER,
  max_streak INTEGER,
  streak_extended BOOLEAN,
  goal_met_today BOOLEAN
) AS $$
DECLARE
  user_target INTEGER;
  now_time TIMESTAMP WITH TIME ZONE;
  last_24h_start TIMESTAMP WITH TIME ZONE;
  last_goal_time TIMESTAMP WITH TIME ZONE;
  grace_hours INTEGER := 4;  -- Renamed variable to avoid ambiguity
  total_protein_24h INTEGER;
  current_streak_val INTEGER := 0;
  max_streak_val INTEGER := 0;
  streak_extended_val BOOLEAN := FALSE;
  goal_met_today_val BOOLEAN := FALSE;
  streak_should_continue BOOLEAN := FALSE;
BEGIN
  -- Get user target (removed auth.users dependency)
  SELECT 
    u.daily_protein_target,
    COALESCE(us.current_streak, 0),
    COALESCE(us.max_streak, 0),
    us.last_goal_timestamp
  INTO user_target, current_streak_val, max_streak_val, last_goal_time
  FROM users u
  LEFT JOIN user_streaks us ON us.user_id = u.id
  WHERE u.id = target_user_id;

  IF user_target IS NULL THEN
    RAISE EXCEPTION 'User not found: %', target_user_id;
  END IF;

  -- Use UTC timezone (can be enhanced later with a timezone column in users table)
  now_time := NOW();
  last_24h_start := now_time - INTERVAL '24 hours';

  -- Get total protein in the last 24 hours
  SELECT COALESCE(SUM(protein_amount), 0)
  INTO total_protein_24h
  FROM meals
  WHERE user_id = target_user_id
    AND created_at >= last_24h_start
    AND created_at <= now_time;

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
        now_time - last_goal_time <= INTERVAL '24 hours' + (grace_hours || ' hours')::INTERVAL
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
       (now_time - last_goal_time <= (grace_hours || ' hours')::INTERVAL) THEN
      -- Still within grace period, don't break streak
      streak_extended_val := FALSE;
    ELSE
      -- Grace period exceeded or no previous goal, check if streak should be broken
      IF last_goal_time IS NOT NULL AND 
         (now_time - last_goal_time > INTERVAL '24 hours' + (grace_hours || ' hours')::INTERVAL) THEN
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
    grace_hours  -- Use the local variable
  )
  ON CONFLICT (user_id)
  DO UPDATE SET
    current_streak = current_streak_val,
    max_streak = max_streak_val,
    last_goal_date = CASE WHEN goal_met_today_val THEN DATE(now_time) ELSE user_streaks.last_goal_date END,
    last_goal_timestamp = CASE WHEN goal_met_today_val THEN now_time ELSE user_streaks.last_goal_timestamp END,
    grace_period_hours = grace_hours,  -- Use the local variable
    updated_at = CURRENT_TIMESTAMP;

  -- Return results
  RETURN QUERY SELECT 
    current_streak_val,
    max_streak_val,
    streak_extended_val,
    goal_met_today_val;
END;
$$ LANGUAGE plpgsql;