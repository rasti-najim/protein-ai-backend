-- Create enum type for logging method
CREATE TYPE logging_method_type AS ENUM ('photo_scan', 'manual_entry');

-- Add logging_method column to meals table
ALTER TABLE meals 
ADD COLUMN logging_method logging_method_type DEFAULT 'manual_entry';