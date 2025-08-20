-- Fix functions to not rely on auth.users.user_metadata which may not exist
-- Instead use a simple timezone approach

-- Updated debug function without user_metadata dependency
CREATE OR REPLACE FUNCTION debug_user_streak(target_user_id UUID)
RETURNS TABLE (
  step TEXT,
  value TEXT,
  success BOOLEAN
) AS $$
DECLARE
  user_target INTEGER;
  user_email TEXT;
  meal_count INTEGER;
  total_protein INTEGER;
  today_protein INTEGER;
  now_time TIMESTAMP WITH TIME ZONE;
  last_24h_start TIMESTAMP WITH TIME ZONE;
BEGIN
  -- Use UTC timezone for simplicity (can be enhanced later)
  now_time := NOW();
  last_24h_start := now_time - INTERVAL '24 hours';
  
  -- Step 1: Check if user exists
  SELECT 
    u.daily_protein_target,
    u.email
  INTO user_target, user_email
  FROM users u
  WHERE u.id = target_user_id;
  
  IF user_email IS NULL THEN
    RETURN QUERY SELECT 'user_exists'::TEXT, 'User not found'::TEXT, FALSE;
    RETURN;
  END IF;
  
  RETURN QUERY SELECT 'user_exists'::TEXT, user_email::TEXT, TRUE;
  RETURN QUERY SELECT 'daily_target'::TEXT, user_target::TEXT, user_target > 0;
  
  -- Step 2: Check total meal count
  SELECT COUNT(*), COALESCE(SUM(protein_amount), 0)
  INTO meal_count, total_protein
  FROM meals 
  WHERE user_id = target_user_id;
  
  RETURN QUERY SELECT 'total_meal_count'::TEXT, meal_count::TEXT, meal_count > 0;
  RETURN QUERY SELECT 'total_protein_ever'::TEXT, total_protein::TEXT, TRUE;
  
  -- Step 3: Check protein in last 24 hours
  SELECT COALESCE(SUM(protein_amount), 0)
  INTO today_protein
  FROM meals 
  WHERE user_id = target_user_id
    AND created_at >= last_24h_start;
  
  RETURN QUERY SELECT 'protein_last_24h'::TEXT, today_protein::TEXT, today_protein >= user_target;
  
  -- Step 4: Check if streak tables exist and have permissions
  BEGIN
    PERFORM 1 FROM user_streaks WHERE user_id = target_user_id LIMIT 1;
    RETURN QUERY SELECT 'user_streaks_access'::TEXT, 'Can access user_streaks'::TEXT, TRUE;
  EXCEPTION WHEN OTHERS THEN
    RETURN QUERY SELECT 'user_streaks_access'::TEXT, SQLERRM::TEXT, FALSE;
  END;
  
  BEGIN
    PERFORM 1 FROM daily_protein_totals WHERE user_id = target_user_id LIMIT 1;
    RETURN QUERY SELECT 'daily_totals_access'::TEXT, 'Can access daily_protein_totals'::TEXT, TRUE;
  EXCEPTION WHEN OTHERS THEN
    RETURN QUERY SELECT 'daily_totals_access'::TEXT, SQLERRM::TEXT, FALSE;
  END;
  
  -- Step 5: Try calling the actual function (but we need to fix it first)
  RETURN QUERY SELECT 'ready_for_streak_test'::TEXT, 'All checks passed - will fix main function next'::TEXT, TRUE;
  
END;
$$ LANGUAGE plpgsql;

-- Fix the main streak function to not depend on auth.users.user_metadata
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
  grace_period_hours INTEGER := 4;
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