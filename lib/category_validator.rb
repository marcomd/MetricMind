# frozen_string_literal: true

# Shared module for validating category names across pattern-based and AI categorization
# Ensures categories are business-focused and not version numbers, issue numbers, or purely numeric
module CategoryValidator
  # Validate category name against business rules
  # @param category [String] Category name to validate
  # @return [Boolean] true if valid, false otherwise
  def self.valid_category?(category)
    return false if category.nil? || category.empty?
    return false if category.length > 50 # Too long
    return false if category.length < 2  # Too short

    # Check if PREVENT_NUMERIC_CATEGORIES is enabled (default: true)
    prevent_numeric = ENV.fetch('PREVENT_NUMERIC_CATEGORIES', 'true').downcase == 'true'

    if prevent_numeric
      # Reject if it's purely numeric (e.g., "2023", "123")
      return false if category.match?(/^\d+$/)

      # Reject if it looks like a version (e.g., "2.58.0", "1.2.3")
      return false if category.match?(/^\d+\.\d+/)

      # Reject if it looks like an issue number (e.g., "#6802", "#117")
      return false if category.match?(/^#\d+$/)

      # Reject if starts with # (but not caught by issue number pattern above)
      return false if category.match?(/^#/)

      # Reject if mostly numbers (>50% digits)
      digit_ratio = category.chars.count { |c| c.match?(/\d/) }.to_f / category.length
      return false if digit_ratio > 0.5
    end

    # Must contain at least one letter
    return false unless category.match?(/[A-Z]/i)

    true
  end

  # Log why a category was rejected (for debugging)
  # @param category [String] Category name that failed validation
  # @return [String] Reason for rejection
  def self.rejection_reason(category)
    return 'nil or empty' if category.nil? || category.empty?
    return 'too long (>50 chars)' if category.length > 50
    return 'too short (<2 chars)' if category.length < 2

    prevent_numeric = ENV.fetch('PREVENT_NUMERIC_CATEGORIES', 'true').downcase == 'true'

    if prevent_numeric
      return 'purely numeric' if category.match?(/^\d+$/)
      return 'looks like version number' if category.match?(/^\d+\.\d+/)
      return 'looks like issue number' if category.match?(/^#\d+$/)
      return 'starts with # symbol' if category.match?(/^#/)

      digit_ratio = category.chars.count { |c| c.match?(/\d/) }.to_f / category.length
      return 'too many digits (>50%)' if digit_ratio > 0.5
    end

    return 'contains no letters' unless category.match?(/[A-Z]/i)

    'valid'
  end
end
