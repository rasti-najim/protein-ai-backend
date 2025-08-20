-- Drop all streak-related database objects

-- 1) Views that depend on streak tables
DROP VIEW IF EXISTS public.user_streak_view;

-- 2) Functions that reference streaks
DROP FUNCTION IF EXISTS public.update_streaks() CASCADE;

-- 3) Indexes specific to streaks
DROP INDEX IF EXISTS public.idx_user_streaks_user;

-- 4) Tables (CASCADE will remove dependent sequences and constraints)
DROP TABLE IF EXISTS public.streaks CASCADE;
DROP TABLE IF EXISTS public.streak_levels CASCADE;


