# frozen_string_literal: true

require 'timeout'
require_relative '../category_validator'

module LLM
  # Abstract base class for LLM clients
  # Provides common interface and error handling for AI categorization
  class BaseClient
    class Error < StandardError; end
    class TimeoutError < Error; end
    class APIError < Error; end
    class ConfigurationError < Error; end

    attr_reader :timeout, :retries, :temperature

    def initialize(timeout: nil, retries: nil, temperature: nil)
      @timeout = timeout || ENV.fetch('AI_TIMEOUT', '30').to_i
      @retries = retries || ENV.fetch('AI_RETRIES', '3').to_i
      @temperature = temperature || 0.1
      validate_configuration!
    end

    # Main interface method - categorize a commit and generate description
    # @param commit_data [Hash] Commit information (subject, hash, files, diff)
    # @param existing_categories [Array<String>] List of approved categories
    # @return [Hash] { category: String, confidence: Integer, description: String }
    def categorize(commit_data, existing_categories)
      raise NotImplementedError, "#{self.class} must implement #categorize"
    end

    protected

    # Execute LLM call with timeout and retry logic
    # @param block [Proc] The API call to execute
    # @return [Object] Result from the block
    def with_retry(&block)
      attempts = 0
      begin
        attempts += 1
        Timeout.timeout(@timeout) { yield }
      rescue Timeout::Error => e
        raise TimeoutError, "LLM request timed out after #{@timeout} seconds: #{e.message}"
      rescue StandardError => e
        if attempts < @retries
          sleep_time = 2**attempts # Exponential backoff
          warn "[LLM] Attempt #{attempts} failed: #{e.message}. Retrying in #{sleep_time}s..."
          sleep(sleep_time)
          retry
        else
          raise APIError, "LLM request failed after #{@retries} attempts: #{e.message}"
        end
      end
    end

    # Validate required configuration is present
    def validate_configuration!
      raise ConfigurationError, 'Timeout must be positive' if @timeout <= 0
      raise ConfigurationError, 'Retries must be non-negative' if @retries.negative?
      raise ConfigurationError, 'Temperature must be between 0 and 2' unless @temperature.between?(0, 2)
    end

    # Build standardized prompt for categorization and description
    # @param commit_data [Hash] Commit information
    # @param existing_categories [Array<String>] List of approved categories
    # @return [String] Formatted prompt
    def build_categorization_prompt(commit_data, existing_categories)
      files_section = if commit_data[:files]&.any?
                        "MODIFIED FILES:\n" + commit_data[:files].map { |f| "- #{f}" }.join("\n")
                      else
                        'MODIFIED FILES: (not available)'
                      end

      diff_section = if commit_data[:diff]
                       truncated_label = commit_data[:diff_truncated] ? ' [TRUNCATED TO 10KB]' : ''
                       "DIFF (changes made)#{truncated_label}:\n```\n#{commit_data[:diff]}\n```"
                     else
                       'DIFF: (not available)'
                     end

      categories_section = if existing_categories.any?
                             "EXISTING CATEGORIES (prefer these):\n#{existing_categories.join(', ')}"
                           else
                             'EXISTING CATEGORIES: (none yet - you can create the first one)'
                           end

      <<~PROMPT
        You are a commit categorization assistant. Analyze this commit, assign ONE category, and write a description.

        COMMIT DETAILS:
        - Subject: "#{commit_data[:subject]}"
        - Hash: #{commit_data[:hash]}

        #{files_section}

        #{diff_section}

        #{categories_section}

        INSTRUCTIONS:
        1. If this clearly fits an existing category, return that category name
        2. Only create a NEW category if none of the existing ones fit well
        3. Categories should be SHORT (1-2 words), UPPERCASE, business-focused
        4. Consider file paths and diff as strong signals (e.g., app/jobs/billing/* → BILLING)
        5. Provide a confidence score (0-100) for your categorization
        6. IMPORTANT: Categories must start with a LETTER, not a number or special character
        7. AVOID: Version numbers (2.58.0), issue numbers (#6802), years (2023), purely numeric values
        8. PREFER: Business domains (BILLING, SECURITY), technical areas (API, DATABASE), or features (AUTH, REPORTING)
        9. Write a DESCRIPTION (2-4 sentences) explaining what changed and why, using the diff details
        10. Assess the BUSINESS_IMPACT (0-100) based on these guidelines:
            - LOW (0-30): Configuration files (yaml, json, etc.)
            - MEDIUM (31-60): Refactors (renames, repetitive changes)
            - HIGH (61-100): Features, bugs, security fixes
            - DEFAULT: Use 100 for typical commits. Only lower if clearly config/refactor work.

        RESPONSE FORMAT (respond with ONLY this format, no extra text):
        CATEGORY: <category_name>
        CONFIDENCE: <0-100>
        BUSINESS_IMPACT: <0-100>
        REASON: <brief explanation>
        DESCRIPTION: <2-4 sentence description of the changes>
      PROMPT
    end

    # Parse LLM response to extract category, confidence, description, and business impact
    # @param response [String] Raw LLM response
    # @return [Hash] { category: String, confidence: Integer, business_impact: Integer, reason: String, description: String }
    def parse_categorization_response(response)
      # Extract category (required) - stop at newline or end of string
      # Allow categories starting with numbers, #, and containing dots so validation can reject them with proper error
      category_match = response.match(/CATEGORY:\s*([A-Z0-9#][A-Z0-9._\s#-]*?)(?:\n|$)/i)
      raise APIError, 'Could not extract category from LLM response' unless category_match

      category = category_match[1].strip.upcase

      # Validate category
      unless valid_category?(category)
        raise APIError, "Invalid category generated by LLM: '#{category}' (failed validation)"
      end

      # Extract confidence (optional, default to 50)
      confidence_match = response.match(/CONFIDENCE:\s*(\d+)/)
      confidence = confidence_match ? confidence_match[1].to_i : 50
      confidence = [[confidence, 0].max, 100].min # Clamp to 0-100

      # Extract business impact (optional, default to 100)
      business_impact_match = response.match(/BUSINESS_IMPACT:\s*(\d+)/i)
      business_impact = business_impact_match ? business_impact_match[1].to_i : 100
      business_impact = [[business_impact, 0].max, 100].min # Clamp to 0-100

      # Extract reason (optional)
      reason_match = response.match(/REASON:\s*(.+?)(?:\n|DESCRIPTION:|$)/im)
      reason = reason_match ? reason_match[1].strip : 'No reason provided'

      # Extract description (optional, can be multi-line)
      description_match = response.match(/DESCRIPTION:\s*(.+?)(?:\n\n|$)/im)
      description = description_match ? description_match[1].strip : nil

      {
        category: category,
        confidence: confidence,
        business_impact: business_impact,
        reason: reason,
        description: description
      }
    end

    # Validate category name using shared validation module
    # @param category [String] Category name to validate
    # @return [Boolean] true if valid
    def valid_category?(category)
      CategoryValidator.valid_category?(category)
    end

    # Log debug information if verbose mode is enabled
    def log_debug(message)
      warn "[LLM::#{self.class.name}] #{message}" if ENV['AI_DEBUG'] == 'true'
    end
  end
end
