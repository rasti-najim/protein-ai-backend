-- Drop weekly meals view and streak levels table

-- 1) Drop the weekly meals view if it exists
DROP VIEW IF EXISTS public.weekly_meals_view;

-- 2) Drop the streak_levels table if it exists
DROP TABLE IF EXISTS public.streak_levels CASCADE;


