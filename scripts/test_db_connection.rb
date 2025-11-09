#!/usr/bin/env ruby
# frozen_string_literal: true

# Simple database connection test script
# Usage: ./scripts/test_db_connection.rb

require 'bundler/setup'
require 'dotenv/load' unless ENV['RSPEC_RUNNING']
require 'pg'
require_relative '../lib/db_connection'

puts "=" * 60
puts "Database Connection Test"
puts "=" * 60
puts ""

# Show connection method being used
if ENV['DATABASE_URL']
  puts "✓ Using DATABASE_URL connection string"
  puts ""
else
  puts "✓ Using individual environment variables"
  puts ""
end

# Get connection parameters
begin
  params = DBConnection.connection_params

  puts "Connection parameters:"
  puts "  Host:     #{params[:host]}"
  puts "  Port:     #{params[:port]}"
  puts "  Database: #{params[:dbname]}"
  puts "  User:     #{params[:user]}"
  puts "  SSL Mode: #{params[:sslmode] || 'not specified'}"
  puts ""

  puts "Attempting to connect..."
  conn = PG.connect(params)

  puts "✓ Connection successful!"
  puts ""

  # Test a simple query
  result = conn.exec('SELECT version()')
  version = result[0]['version']

  puts "PostgreSQL version:"
  puts "  #{version}"
  puts ""

  # Check if our schema exists
  result = conn.exec(<<~SQL)
    SELECT table_name
    FROM information_schema.tables
    WHERE table_schema = 'public'
    AND table_name IN ('repositories', 'commits', 'users')
    ORDER BY table_name
  SQL

  if result.ntuples > 0
    puts "Schema check:"
    result.each do |row|
      puts "  ✓ Table '#{row['table_name']}' exists"
    end
    puts ""
  else
    puts "⚠️  Warning: Schema not initialized yet"
    puts "   Run: ./scripts/setup.sh --database-only"
    puts ""
  end

  conn.close

  puts "=" * 60
  puts "✅ Test completed successfully!"
  puts "=" * 60

rescue PG::Error => e
  puts "❌ Connection failed!"
  puts ""
  puts "Error: #{e.message}"
  puts ""
  puts "Troubleshooting:"
  puts "  1. Check your connection parameters in .env file"
  puts "  2. Ensure PostgreSQL is running"
  puts "  3. Verify database exists"
  puts "  4. Check firewall/network settings (for remote databases)"
  puts "  5. Verify SSL requirements (for remote databases)"
  puts ""
  exit 1
rescue StandardError => e
  puts "❌ Unexpected error: #{e.message}"
  puts e.backtrace.join("\n")
  exit 1
end
