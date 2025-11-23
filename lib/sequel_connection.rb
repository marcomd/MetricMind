# frozen_string_literal: true

require 'sequel'
require_relative 'db_connection'

# Sequel database connection helper module
# Wraps DBConnection to provide Sequel-compatible database instance
module SequelConnection
  # Get Sequel database instance
  # Priority: DATABASE_URL > individual env vars > defaults
  #
  # @return [Sequel::Database] Sequel database connection
  def self.db
    if ENV['DATABASE_URL']
      # Sequel can directly parse PostgreSQL URLs
      Sequel.connect(ENV['DATABASE_URL'])
    else
      # Convert DBConnection params to Sequel format
      params = DBConnection.connection_params
      Sequel.connect(
        adapter: 'postgres',
        host: params[:host],
        port: params[:port],
        database: params[:dbname],
        user: params[:user],
        password: params[:password],
        sslmode: params[:sslmode]
      )
    end
  end

  # Get connection string for psql commands
  # Useful for scripts that still need to shell out to psql
  #
  # @return [String] PostgreSQL connection string
  def self.connection_string
    if ENV['DATABASE_URL']
      ENV['DATABASE_URL']
    else
      params = DBConnection.connection_params
      password_part = params[:password] ? ":#{params[:password]}" : ''
      "postgresql://#{params[:user]}#{password_part}@#{params[:host]}:#{params[:port]}/#{params[:dbname]}"
    end
  end

  # Get database name from current connection parameters
  #
  # @return [String] Database name
  def self.database_name
    if ENV['DATABASE_URL']
      uri = URI.parse(ENV['DATABASE_URL'])
      uri.path[1..] # Remove leading slash
    else
      DBConnection.connection_params[:dbname]
    end
  end
end
