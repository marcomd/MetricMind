# frozen_string_literal: true

# Migration: Add users table for Google OAuth authentication
# Original file: 002_add_users_and_oauth.sql
# Original date: 2025-11-09
# Converted from SQL to Sequel format

Sequel.migration do
  up do
    run <<-SQL
      CREATE TABLE IF NOT EXISTS users (
          id SERIAL PRIMARY KEY,
          google_id VARCHAR(255) NOT NULL UNIQUE,
          email VARCHAR(255) NOT NULL UNIQUE,
          name VARCHAR(255),
          domain VARCHAR(255) NOT NULL,
          avatar_url TEXT,
          created_at TIMESTAMP DEFAULT NOW(),
          updated_at TIMESTAMP DEFAULT NOW(),
          last_login TIMESTAMP DEFAULT NOW()
      );
      
      CREATE INDEX IF NOT EXISTS idx_users_google_id ON users(google_id);
      CREATE INDEX IF NOT EXISTS idx_users_email ON users(email);
      
      COMMENT ON TABLE users IS 'Stores user accounts authenticated via Google OAuth';
      COMMENT ON COLUMN users.google_id IS 'Unique Google user identifier from OAuth';
      COMMENT ON COLUMN users.email IS 'User email address from Google OAuth profile';
      COMMENT ON COLUMN users.name IS 'Display name from Google OAuth profile';
      COMMENT ON COLUMN users.domain IS 'Email domain extracted from email address, used for access control';
      COMMENT ON COLUMN users.avatar_url IS 'Profile picture URL from Google OAuth';
      COMMENT ON COLUMN users.created_at IS 'Timestamp when the user account was created';
      COMMENT ON COLUMN users.updated_at IS 'Timestamp when the user record was last updated';
      COMMENT ON COLUMN users.last_login IS 'Timestamp of the most recent login';
    SQL
  end

  down do
    run <<-SQL
      DROP INDEX IF EXISTS idx_users_email;
            DROP INDEX IF EXISTS idx_users_google_id;
            DROP TABLE IF EXISTS users CASCADE;
    SQL
  end
end
