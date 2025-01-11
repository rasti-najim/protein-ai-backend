CREATE TABLE streak_levels (
  id SERIAL PRIMARY KEY,
  threshold INT NOT NULL,
  name TEXT NOT NULL,
  emoji TEXT NOT NULL,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

INSERT INTO streak_levels (threshold, name, emoji) VALUES
(1, 'Starter', '🌱'),
(3, 'Habit', '🌿'),
(7, 'Fuel', '🍃'),
(14, 'Growth', '🌴'),
(30, 'Sustenance', '🌳'),
(90, 'Harmony', '🌍'),
(365, 'Summit', '🌄');