-- Remove old cron jobs that reference the dropped update_streaks() function

-- Unschedule any jobs that might be calling the old update_streaks function
-- These job names are common patterns used in previous migrations
DO $$
DECLARE
  job_name TEXT;
BEGIN
  -- List of potential job names that might reference update_streaks
  FOR job_name IN 
    SELECT unnest(ARRAY['update-streaks', 'update_streaks', 'streak-update', 'daily-streak-update', 'streak-maintenance-old'])
  LOOP
    BEGIN
      PERFORM cron.unschedule(job_name);
      RAISE LOG 'Unscheduled cron job: %', job_name;
    EXCEPTION
      WHEN OTHERS THEN
        -- Job might not exist, continue
        NULL;
    END;
  END LOOP;
END $$;

-- Also check for any remaining cron jobs and clean them up
-- This will show all current cron jobs so we can identify the problematic one
DO $$
DECLARE
  job_record RECORD;
BEGIN
  -- Log all current cron jobs for debugging
  FOR job_record IN 
    SELECT jobname, command 
    FROM cron.job 
    WHERE command LIKE '%update_streaks%'
  LOOP
    RAISE LOG 'Found job calling update_streaks: % - %', job_record.jobname, job_record.command;
    -- Unschedule it
    PERFORM cron.unschedule(job_record.jobname);
    RAISE LOG 'Unscheduled problematic job: %', job_record.jobname;
  END LOOP;
END $$;