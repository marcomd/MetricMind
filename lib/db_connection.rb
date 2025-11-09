# frozen_string_literal: true

require 'uri'
require 'cgi'

# Database connection helper module
# Supports both DATABASE_URL connection string (priority) and individual env vars
module DBConnection
  # Get database connection parameters
  # Priority: DATABASE_URL > individual env vars > defaults
  #
  # @return [Hash] Connection parameters for PG.connect
  def self.connection_params
    if ENV['DATABASE_URL']
      parse_database_url(ENV['DATABASE_URL'])
    else
      individual_env_params
    end
  end

  # Parse DATABASE_URL connection string
  # Format: postgresql://user:password@host:port/database?sslmode=require
  #
  # @param url [String] PostgreSQL connection URL
  # @return [Hash] Connection parameters
  def self.parse_database_url(url)
    uri = URI.parse(url)

    # Extract query parameters (e.g., sslmode, channel_binding)
    query_params = if uri.query
                     CGI.parse(uri.query).transform_values(&:first)
                   else
                     {}
                   end

    # Build connection hash
    params = {
      host: uri.host,
      port: uri.port || 5432,
      dbname: uri.path[1..], # Remove leading slash
      user: uri.user,
      password: uri.password
    }

    # Add SSL mode if specified
    params[:sslmode] = query_params['sslmode'] if query_params['sslmode']

    params.compact
  end

  # Build connection parameters from individual environment variables
  #
  # @return [Hash] Connection parameters
  def self.individual_env_params
    {
      host: ENV['PGHOST'] || 'localhost',
      port: ENV['PGPORT'] || 5432,
      dbname: ENV['PGDATABASE'] || 'git_analytics',
      user: ENV['PGUSER'] || ENV['USER'],
      password: ENV['PGPASSWORD']
    }.compact
  end
end
