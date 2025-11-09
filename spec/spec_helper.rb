# frozen_string_literal: true

require 'json'
require 'tempfile'
require 'fileutils'

# Configure test database
# Set an environment variable to prevent dotenv from loading during tests
ENV['RSPEC_RUNNING'] = 'true'

# Clear DATABASE_URL so tests use local database with individual env vars
ENV.delete('DATABASE_URL')

# Set test database name
if ENV['PGDATABASE_TEST']
  ENV['PGDATABASE'] = ENV['PGDATABASE_TEST']
elsif ENV['PGDATABASE'] && !ENV['PGDATABASE'].end_with?('_test')
  ENV['PGDATABASE'] = "#{ENV['PGDATABASE']}_test"
else
  ENV['PGDATABASE'] = 'git_analytics_test'
end

RSpec.configure do |config|
  config.expect_with :rspec do |expectations|
    expectations.include_chain_clauses_in_custom_matcher_descriptions = true
  end

  config.mock_with :rspec do |mocks|
    mocks.verify_partial_doubles = true
  end

  config.shared_context_metadata_behavior = :apply_to_host_groups
  config.filter_run_when_matching :focus
  config.example_status_persistence_file_path = 'spec/examples.txt'
  config.disable_monkey_patching!
  config.warnings = true

  if config.files_to_run.one?
    config.default_formatter = 'doc'
  end

  config.profile_examples = 10
  config.order = :random
  Kernel.srand config.seed
end
