# frozen_string_literal: true

require 'pg'
require 'json'
require_relative 'client_factory'
require_relative '../db_connection'

module LLM
  # High-level AI categorization orchestrator
  # Manages category database, LLM client interaction, and commit updates
  class Categorizer
    attr_reader :client, :conn, :stats

    def initialize(client: nil, conn: nil)
      @client = client || ClientFactory.create
      @conn = conn || PG.connect(DBConnection.connection_params)
      @stats = {
        processed: 0,
        categorized: 0,
        errors: 0,
        new_categories: 0
      }
    end

    # Categorize a batch of commits using AI
    # @param commits [Array<Hash>] Commits to categorize (from database)
    # @param json_data [Hash] JSON export data with file information
    # @param batch_size [Integer] Number of commits to process before committing transaction
    # @return [Hash] Statistics about the categorization process
    def categorize_commits(commits, json_data, batch_size: 50)
      existing_categories = fetch_existing_categories

      commits.each_slice(batch_size) do |batch|
        process_batch(batch, json_data, existing_categories)
      end

      @stats
    end

    # Fetch existing categories from database
    # @return [Array<String>] List of category names
    def fetch_existing_categories
      result = @conn.exec('SELECT name FROM categories ORDER BY usage_count DESC, name ASC')
      result.map { |row| row['name'] }
    end

    # Save a new category to the database
    # @param category_name [String] Category name
    # @param description [String, nil] Optional description
    # @return [Boolean] true if created, false if already exists
    def save_category(category_name, description: nil)
      description ||= 'Created by AI categorization'

      result = @conn.exec_params(
        'INSERT INTO categories (name, description, usage_count) VALUES ($1, $2, 1) ON CONFLICT (name) DO NOTHING',
        [category_name, description]
      )

      @stats[:new_categories] += 1 if result.cmd_tuples == 1
      true
    rescue PG::Error => e
      warn "[Categorizer] Failed to save category #{category_name}: #{e.message}"
      false
    end

    # Update commit with AI categorization
    # @param commit_hash [String] Git commit hash
    # @param category [String] Category name
    # @param confidence [Integer] Confidence score (0-100)
    # @param repository_id [Integer] Repository ID
    # @return [Boolean] true if updated successfully
    def update_commit(commit_hash, category, confidence, repository_id)
      @conn.exec_params(
        'UPDATE commits SET category = $1, ai_confidence = $2 WHERE hash = $3 AND repository_id = $4',
        [category, confidence, commit_hash, repository_id]
      )

      # Update category usage count
      @conn.exec_params(
        'UPDATE categories SET usage_count = usage_count + 1 WHERE name = $1',
        [category]
      )

      true
    rescue PG::Error => e
      warn "[Categorizer] Failed to update commit #{commit_hash}: #{e.message}"
      false
    end

    # Find commit data in JSON export by hash
    # @param json_data [Hash] JSON export data
    # @param commit_hash [String] Git commit hash
    # @return [Hash, nil] Commit data with files, or nil if not found
    def find_commit_in_json(json_data, commit_hash)
      json_data['commits']&.find { |c| c['hash'] == commit_hash }
    end

    # Close database connection
    def close
      @conn.close if @conn && !@conn.finished?
    end

    private

    def process_batch(batch, json_data, existing_categories)
      @conn.transaction do
        batch.each do |commit|
          process_single_commit(commit, json_data, existing_categories)
        end
      end
    rescue PG::Error => e
      warn "[Categorizer] Batch transaction failed: #{e.message}"
      @stats[:errors] += batch.size
    end

    def process_single_commit(commit, json_data, existing_categories)
      @stats[:processed] += 1

      # Find commit in JSON to get file list
      json_commit = find_commit_in_json(json_data, commit['hash'])
      files = extract_file_paths(json_commit)

      # Prepare commit data for LLM
      commit_data = {
        hash: commit['hash'],
        subject: commit['subject'],
        files: files
      }

      # Call LLM for categorization
      result = @client.categorize(commit_data, existing_categories)

      # Save new category if needed
      unless existing_categories.include?(result[:category])
        if save_category(result[:category], description: result[:reason])
          existing_categories << result[:category]
        end
      end

      # Update commit in database
      if update_commit(commit['hash'], result[:category], result[:confidence], commit['repository_id'])
        @stats[:categorized] += 1
        log_categorization(commit, result)
      else
        @stats[:errors] += 1
      end
    rescue BaseClient::Error => e
      warn "[Categorizer] LLM error for commit #{commit['hash']}: #{e.message}"
      @stats[:errors] += 1
    rescue StandardError => e
      warn "[Categorizer] Unexpected error for commit #{commit['hash']}: #{e.message}"
      @stats[:errors] += 1
    end

    def extract_file_paths(json_commit)
      return [] unless json_commit && json_commit['files']

      json_commit['files'].map do |file|
        # Remove trailing newline if present
        file['filename']&.strip || file['path']&.strip
      end.compact
    end

    def log_categorization(commit, result)
      if ENV['AI_DEBUG'] == 'true'
        puts "[AI] #{commit['hash'][0..7]}: #{result[:category]} (confidence: #{result[:confidence]}%)"
        puts "     Subject: #{commit['subject']}"
        puts "     Reason: #{result[:reason]}"
      end
    end
  end
end
