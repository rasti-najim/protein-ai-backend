-- Fix streak maintenance cron job by enabling pg_net extension
-- or falling back to alternative method

-- Try to enable pg_net extension (available in Supabase)
CREATE EXTENSION IF NOT EXISTS pg_net;

-- If pg_net is not available, we'll update the cron job to use a simpler approach
-- that calls the function directly instead of making HTTP requests

-- Create a direct streak maintenance function that doesn't require HTTP calls
CREATE OR REPLACE FUNCTION direct_streak_maintenance()
RETURNS TEXT AS $$
DECLARE
  expired_count INTEGER := 0;
  expired_user_ids UUID[];
  current_time TIMESTAMP WITH TIME ZONE := NOW();
  streak_record RECORD;
  expiration_time TIMESTAMP WITH TIME ZONE;
  grace_period_hours INTEGER;
BEGIN
  -- Find users with active streaks that should be expired
  FOR streak_record IN
    SELECT 
      us.user_id,
      us.current_streak,
      us.last_goal_timestamp,
      COALESCE(us.grace_period_hours, 4) as grace_period_hours
    FROM user_streaks us
    WHERE us.current_streak > 0 
      AND us.last_goal_timestamp IS NOT NULL
  LOOP
    grace_period_hours := streak_record.grace_period_hours;
    expiration_time := streak_record.last_goal_timestamp + 
                      INTERVAL '24 hours' + 
                      (grace_period_hours || ' hours')::INTERVAL;
    
    -- Check if streak should be expired
    IF current_time > expiration_time THEN
      expired_user_ids := array_append(expired_user_ids, streak_record.user_id);
      expired_count := expired_count + 1;
      
      RAISE LOG 'Streak expired for user %: last goal at %, expired at %', 
                streak_record.user_id, 
                streak_record.last_goal_timestamp, 
                expiration_time;
    END IF;
  END LOOP;

  -- Batch update expired streaks
  IF array_length(expired_user_ids, 1) > 0 THEN
    UPDATE user_streaks 
    SET 
      current_streak = 0,
      updated_at = current_time
    WHERE user_id = ANY(expired_user_ids);
    
    RAISE LOG 'Successfully broke % expired streaks', expired_count;
  END IF;

  -- Clean up old daily_protein_totals records (keep last 30 days)
  DELETE FROM daily_protein_totals 
  WHERE date < (current_time - INTERVAL '30 days')::DATE;

  RAISE LOG 'Streak maintenance completed: % streaks expired at %', 
            expired_count, current_time;

  RETURN 'Streak maintenance completed. ' || expired_count || ' streaks expired at ' || current_time::TEXT;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Drop the existing cron job
SELECT cron.unschedule('streak-maintenance');

-- Schedule the new direct function every 2 hours
SELECT cron.schedule(
  'streak-maintenance-direct',           -- job name
  '0 */2 * * *',                        -- every 2 hours at minute 0 (UTC)
  'SELECT direct_streak_maintenance();'  -- call our direct function
);

-- Grant necessary permissions
GRANT EXECUTE ON FUNCTION direct_streak_maintenance() TO postgres;

-- Log the fix
DO $$
BEGIN
  RAISE LOG 'Streak maintenance cron job fixed - switched from HTTP calls to direct database function';
END $$;