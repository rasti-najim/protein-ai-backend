-- Create simple streak tracking system

-- Table to track user streaks
CREATE TABLE user_streaks (
  user_id UUID PRIMARY KEY REFERENCES users (id) ON DELETE CASCADE,
  current_streak INTEGER NOT NULL DEFAULT 0,
  max_streak INTEGER NOT NULL DEFAULT 0,
  last_goal_date DATE,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- Table to cache daily protein totals for efficient streak calculation
CREATE TABLE daily_protein_totals (
  user_id UUID NOT NULL REFERENCES users (id) ON DELETE CASCADE,
  date DATE NOT NULL,
  total_protein INTEGER NOT NULL DEFAULT 0,
  goal_met BOOLEAN NOT NULL DEFAULT FALSE,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (user_id, date)
);

-- Index for efficient streak queries
CREATE INDEX idx_daily_protein_totals_user_date ON daily_protein_totals (user_id, date DESC);
CREATE INDEX idx_user_streaks_current ON user_streaks (current_streak DESC);

-- Function to calculate and update user streak
CREATE OR REPLACE FUNCTION update_user_streak(target_user_id UUID)
RETURNS TABLE (
  current_streak INTEGER,
  max_streak INTEGER,
  streak_extended BOOLEAN,
  goal_met_today BOOLEAN
) AS $$
DECLARE
  user_timezone TEXT;
  today_date DATE;
  yesterday_date DATE;
  today_total INTEGER;
  user_target INTEGER;
  current_streak_val INTEGER := 0;
  max_streak_val INTEGER := 0;
  streak_extended_val BOOLEAN := FALSE;
  goal_met_today_val BOOLEAN := FALSE;
BEGIN
  -- Get user timezone and target
  SELECT 
    COALESCE(user_metadata->>'timezone', 'UTC'),
    daily_protein_target
  INTO user_timezone, user_target
  FROM auth.users au
  JOIN users u ON u.id = au.id
  WHERE u.id = target_user_id;

  -- Calculate today's date in user timezone
  today_date := DATE(NOW() AT TIME ZONE user_timezone);
  yesterday_date := today_date - INTERVAL '1 day';

  -- Get today's total protein intake
  SELECT COALESCE(SUM(protein_amount), 0)
  INTO today_total
  FROM meals
  WHERE user_id = target_user_id
    AND DATE(created_at AT TIME ZONE user_timezone) = today_date;

  -- Check if goal is met today
  goal_met_today_val := today_total >= user_target;

  -- Update or insert today's total
  INSERT INTO daily_protein_totals (user_id, date, total_protein, goal_met)
  VALUES (target_user_id, today_date, today_total, goal_met_today_val)
  ON CONFLICT (user_id, date) 
  DO UPDATE SET 
    total_protein = today_total,
    goal_met = goal_met_today_val,
    updated_at = CURRENT_TIMESTAMP;

  -- Get current streak info
  SELECT 
    COALESCE(us.current_streak, 0),
    COALESCE(us.max_streak, 0)
  INTO current_streak_val, max_streak_val
  FROM user_streaks us
  WHERE us.user_id = target_user_id;

  -- Calculate new streak
  IF goal_met_today_val THEN
    -- Check if we met yesterday's goal to continue streak
    IF EXISTS (
      SELECT 1 FROM daily_protein_totals 
      WHERE user_id = target_user_id 
        AND date = yesterday_date 
        AND goal_met = TRUE
    ) THEN
      -- Continue streak if yesterday was met, or start new streak
      SELECT COALESCE(us.last_goal_date, today_date - INTERVAL '2 days') = yesterday_date
      INTO streak_extended_val
      FROM user_streaks us
      WHERE us.user_id = target_user_id;
      
      IF streak_extended_val THEN
        current_streak_val := current_streak_val + 1;
        streak_extended_val := TRUE;
      ELSE
        current_streak_val := 1;
        streak_extended_val := FALSE;
      END IF;
    ELSE
      -- Start new streak
      current_streak_val := 1;
      streak_extended_val := FALSE;
    END IF;
    
    -- Update max streak if needed
    max_streak_val := GREATEST(max_streak_val, current_streak_val);
  END IF;

  -- Insert or update user streak
  INSERT INTO user_streaks (user_id, current_streak, max_streak, last_goal_date)
  VALUES (target_user_id, current_streak_val, max_streak_val, 
          CASE WHEN goal_met_today_val THEN today_date ELSE NULL END)
  ON CONFLICT (user_id)
  DO UPDATE SET
    current_streak = current_streak_val,
    max_streak = max_streak_val,
    last_goal_date = CASE WHEN goal_met_today_val THEN today_date ELSE user_streaks.last_goal_date END,
    updated_at = CURRENT_TIMESTAMP;

  -- Return results
  RETURN QUERY SELECT 
    current_streak_val,
    max_streak_val,
    streak_extended_val,
    goal_met_today_val;
END;
$$ LANGUAGE plpgsql;