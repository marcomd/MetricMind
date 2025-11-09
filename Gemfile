# frozen_string_literal: true

source 'https://rubygems.org'

# Ruby version (adjust as needed)
ruby '>= 3.3.0'

# Database connector for PostgreSQL
gem 'pg', '~> 1.5'

# Environment variable management
gem 'dotenv', '~> 2.8'

group :development, :test do
  gem 'rspec', '~> 3.12'
  gem 'rubocop', '~> 1.50', require: false
  gem 'rubocop-rspec', '~> 2.20', require: false
end

# JSON is part of stdlib, but explicitly add for clarity
# No additional gems needed for core functionality
