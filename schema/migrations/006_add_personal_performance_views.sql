-- Migration: Add personal performance views
-- Version: 006
-- Description: Adds views for personal performance metrics filtered by author_email
--              Supports personal metrics on Trends, Activity, and Content pages
-- Dependencies: Requires commits table with author_email, author_name, weight columns

-- Apply the personal performance views
\i schema/personal_views.sql
