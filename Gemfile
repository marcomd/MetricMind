# frozen_string_literal: true

source 'https://rubygems.org'

# Ruby version (adjust as needed)
ruby '>= 3.3.0'

# Database connector for PostgreSQL
gem 'pg', '~> 1.5'

# Database migration framework
gem 'sequel', '~> 5.75'

# Environment variable management
gem 'dotenv', '~> 2.8'

# LLM integration for AI-powered categorization
gem 'langchainrb', '~> 0.17'
gem 'ruby-anthropic', '~> 0.4' # Required for Anthropic/Claude provider (langchainrb dependency)

# HTTP client with retry support
gem 'faraday', '~> 2.7'
gem 'faraday-retry', '~> 2.2'

group :development, :test do
  gem 'rspec', '~> 3.12'
  gem 'rubocop', '~> 1.50', require: false
  gem 'rubocop-rspec', '~> 2.20', require: false
end

# JSON is part of stdlib, but explicitly add for clarity
# No additional gems needed for core functionality
