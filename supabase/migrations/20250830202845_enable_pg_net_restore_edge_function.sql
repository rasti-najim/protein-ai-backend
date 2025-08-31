-- Enable pg_net extension and restore original edge function cron job approach

-- Enable the pg_net extension for HTTP requests
CREATE EXTENSION IF NOT EXISTS pg_net;

-- Remove the direct database function and its cron job
SELECT cron.unschedule('streak-maintenance-direct');
DROP FUNCTION IF EXISTS direct_streak_maintenance();

-- Restore the original edge function approach
-- This is the working version from the original migration
CREATE OR REPLACE FUNCTION call_streak_maintenance_simple()
RETURNS TEXT AS $$
BEGIN
  -- Make HTTP request to our Edge Function
  PERFORM net.http_post(
    url := current_setting('app.supabase_url') || '/functions/v1/streak-maintenance',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'Authorization', 'Bearer ' || current_setting('app.cron_secret')
    ),
    body := '{}'::jsonb
  );
  
  RAISE LOG 'Streak maintenance Edge Function called at %', NOW();
  
  RETURN 'Streak maintenance triggered at ' || NOW()::TEXT;
END;
$$ LANGUAGE plpgsql;

-- Schedule the cron job to call our Edge Function every 2 hours
SELECT cron.schedule(
  'streak-maintenance',                    -- job name (back to original)
  '0 */2 * * *',                          -- every 2 hours at minute 0 (UTC)
  'SELECT call_streak_maintenance_simple();' -- call our function
);

-- Grant necessary permissions
GRANT EXECUTE ON FUNCTION call_streak_maintenance_simple() TO postgres;

-- Log the restoration
DO $$
BEGIN
  RAISE LOG 'Restored edge function approach for streak maintenance with pg_net extension enabled';
END $$;