-- Debug function to test streak system
CREATE OR REPLACE FUNCTION debug_user_streak(target_user_id UUID)
RETURNS TABLE (
  step TEXT,
  value TEXT,
  success BOOLEAN
) AS $$
DECLARE
  user_timezone TEXT;
  user_target INTEGER;
  user_email TEXT;
  meal_count INTEGER;
  total_protein INTEGER;
BEGIN
  -- Step 1: Check if user exists
  SELECT 
    COALESCE(au.user_metadata->>'timezone', 'UTC'),
    u.daily_protein_target,
    au.email
  INTO user_timezone, user_target, user_email
  FROM auth.users au
  JOIN users u ON u.id = au.id
  WHERE u.id = target_user_id;
  
  IF user_email IS NULL THEN
    RETURN QUERY SELECT 'user_exists'::TEXT, 'User not found'::TEXT, FALSE;
    RETURN;
  END IF;
  
  RETURN QUERY SELECT 'user_exists'::TEXT, user_email::TEXT, TRUE;
  RETURN QUERY SELECT 'user_timezone'::TEXT, user_timezone::TEXT, TRUE;
  RETURN QUERY SELECT 'daily_target'::TEXT, user_target::TEXT, user_target > 0;
  
  -- Step 2: Check meal count
  SELECT COUNT(*), COALESCE(SUM(protein_amount), 0)
  INTO meal_count, total_protein
  FROM meals 
  WHERE user_id = target_user_id;
  
  RETURN QUERY SELECT 'meal_count'::TEXT, meal_count::TEXT, meal_count > 0;
  RETURN QUERY SELECT 'total_protein'::TEXT, total_protein::TEXT, total_protein >= user_target;
  
  -- Step 3: Check if streak tables exist and have permissions
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
  
  -- Step 4: Try calling the actual function
  BEGIN
    PERFORM update_user_streak(target_user_id);
    RETURN QUERY SELECT 'function_call'::TEXT, 'update_user_streak succeeded'::TEXT, TRUE;
  EXCEPTION WHEN OTHERS THEN
    RETURN QUERY SELECT 'function_call'::TEXT, SQLERRM::TEXT, FALSE;
  END;
  
END;
$$ LANGUAGE plpgsql;

-- Grant permissions for debugging
GRANT EXECUTE ON FUNCTION debug_user_streak(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION debug_user_streak(UUID) TO anon;