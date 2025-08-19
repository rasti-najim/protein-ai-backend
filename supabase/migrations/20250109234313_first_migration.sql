-- Create enum types first (before table creation)
CREATE TYPE gender_type AS ENUM ('male', 'female', 'other');
CREATE TYPE exercise_frequency_type AS ENUM ('0-2', '3-4', '5+');
CREATE TYPE weight_unit_type AS ENUM ('kg', 'lbs');
CREATE TYPE goal_type AS ENUM ('lose', 'maintain', 'gain');

-- Then modify your table to use these enums
CREATE TABLE users (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid() REFERENCES auth.users (id) ON DELETE CASCADE,
  email TEXT NOT NULL,
  gender gender_type NOT NULL,
  exercise_frequency exercise_frequency_type NOT NULL,
  target_weight INTEGER NOT NULL,
  target_weight_unit weight_unit_type NOT NULL,
  goal goal_type NOT NULL,
  daily_protein_target INTEGER NOT NULL,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE meals (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES users (id) ON DELETE CASCADE,
  name TEXT NOT NULL,
  protein_amount INTEGER NOT NULL,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);


