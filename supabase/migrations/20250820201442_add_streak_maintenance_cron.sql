-- Enable pg_cron extension for scheduled jobs
CREATE EXTENSION IF NOT EXISTS pg_cron;

-- Create a function that calls our streak-maintenance Edge Function
CREATE OR REPLACE FUNCTION call_streak_maintenance()
RETURNS TEXT AS $$
DECLARE
  result TEXT;
  request_id BIGINT;
BEGIN
  -- Call the streak-maintenance Edge Function via HTTP
  SELECT 
    http.http_post(
      url := current_setting('app.supabase_url') || '/functions/v1/streak-maintenance',
      body := '{}',
      headers := jsonb_build_object(
        'Content-Type', 'application/json',
        'Authorization', 'Bearer ' || current_setting('app.cron_secret')
      )
    ) INTO request_id;
  
  -- Get the response (this is async, so we get the request_id)
  SELECT content::TEXT 
  FROM http_response 
  WHERE id = request_id 
  INTO result;
  
  -- Log the result
  RAISE LOG 'Streak maintenance cron job result: %', COALESCE(result, 'No response');
  
  RETURN COALESCE(result, 'Request submitted with ID: ' || request_id::TEXT);
END;
$$ LANGUAGE plpgsql;

-- Alternative simpler approach using pg_net (if available)
-- This approach is more reliable for Edge Function calls
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

-- Set configuration for the Edge Function URL and secret
-- These should be set as Supabase database secrets/settings
-- ALTER DATABASE postgres SET app.supabase_url = 'https://your-project.supabase.co';
-- ALTER DATABASE postgres SET app.cron_secret = 'your-cron-secret';

-- Schedule the cron job to call our Edge Function every 2 hours
SELECT cron.schedule(
  'streak-maintenance',                    -- job name
  '0 */2 * * *',                          -- every 2 hours at minute 0 (UTC)
  'SELECT call_streak_maintenance_simple();' -- call our function
);

-- Grant necessary permissions
GRANT EXECUTE ON FUNCTION call_streak_maintenance() TO postgres;
GRANT EXECUTE ON FUNCTION call_streak_maintenance_simple() TO postgres;