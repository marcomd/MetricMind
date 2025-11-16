# frozen_string_literal: true

require 'spec_helper'
require_relative '../../lib/llm/base_client'

RSpec.describe LLM::BaseClient do
  # Create a concrete test class since BaseClient is abstract
  let(:test_client_class) do
    Class.new(LLM::BaseClient) do
      def categorize(commit_data, existing_categories)
        'test implementation'
      end
    end
  end

  let(:client) { test_client_class.new }

  describe '#initialize' do
    it 'sets default values from ENV' do
      expect(client.timeout).to eq(30)
      expect(client.retries).to eq(3)
      expect(client.temperature).to eq(0.1)
    end

    it 'accepts custom values' do
      custom_client = test_client_class.new(timeout: 60, retries: 5, temperature: 0.5)
      expect(custom_client.timeout).to eq(60)
      expect(custom_client.retries).to eq(5)
      expect(custom_client.temperature).to eq(0.5)
    end

    it 'raises error for invalid timeout' do
      expect { test_client_class.new(timeout: 0) }.to raise_error(LLM::BaseClient::ConfigurationError)
    end

    it 'raises error for invalid retries' do
      expect { test_client_class.new(retries: -1) }.to raise_error(LLM::BaseClient::ConfigurationError)
    end

    it 'raises error for invalid temperature' do
      expect { test_client_class.new(temperature: 3) }.to raise_error(LLM::BaseClient::ConfigurationError)
    end
  end

  describe '#valid_category?' do
    context 'with PREVENT_NUMERIC_CATEGORIES enabled (default)' do
      before { ENV['PREVENT_NUMERIC_CATEGORIES'] = 'true' }
      after { ENV.delete('PREVENT_NUMERIC_CATEGORIES') }

      it 'accepts valid category names' do
        expect(client.send(:valid_category?, 'BILLING')).to be true
        expect(client.send(:valid_category?, 'CS')).to be true
        expect(client.send(:valid_category?, 'API_INTEGRATION')).to be true
        expect(client.send(:valid_category?, 'TECH-DEBT')).to be true
      end

      it 'rejects nil or empty categories' do
        expect(client.send(:valid_category?, nil)).to be false
        expect(client.send(:valid_category?, '')).to be false
      end

      it 'rejects categories that are too short' do
        expect(client.send(:valid_category?, 'A')).to be false
      end

      it 'rejects categories that are too long' do
        long_category = 'A' * 51
        expect(client.send(:valid_category?, long_category)).to be false
      end

      it 'rejects categories starting with numbers' do
        expect(client.send(:valid_category?, '2FA')).to be false
        expect(client.send(:valid_category?, '123')).to be false
      end

      it 'rejects categories starting with special characters' do
        expect(client.send(:valid_category?, '#6802')).to be false
        expect(client.send(:valid_category?, '#117')).to be false
      end

      it 'rejects purely numeric categories' do
        expect(client.send(:valid_category?, '2023')).to be false
        expect(client.send(:valid_category?, '123456')).to be false
      end

      it 'rejects version number categories' do
        expect(client.send(:valid_category?, '2.58.0')).to be false
        expect(client.send(:valid_category?, '1.2.3')).to be false
        expect(client.send(:valid_category?, '2.19.0')).to be false
      end

      it 'rejects issue number categories' do
        expect(client.send(:valid_category?, '#6802')).to be false
        expect(client.send(:valid_category?, '#117')).to be false
      end

      it 'rejects categories with >50% digits' do
        expect(client.send(:valid_category?, 'A123456')).to be false
      end

      it 'rejects categories without letters' do
        expect(client.send(:valid_category?, '###')).to be false
        expect(client.send(:valid_category?, '---')).to be false
      end
    end

    context 'with PREVENT_NUMERIC_CATEGORIES disabled' do
      before { ENV['PREVENT_NUMERIC_CATEGORIES'] = 'false' }
      after { ENV.delete('PREVENT_NUMERIC_CATEGORIES') }

      it 'allows numeric categories' do
        expect(client.send(:valid_category?, '2FA')).to be true
        expect(client.send(:valid_category?, 'API2')).to be true
      end

      it 'still requires at least one letter' do
        expect(client.send(:valid_category?, '123')).to be false
      end
    end
  end

  describe '#parse_categorization_response' do
    it 'parses valid response with all fields' do
      response = <<~RESPONSE
        CATEGORY: BILLING
        CONFIDENCE: 85
        REASON: Commit modifies billing-related files
      RESPONSE

      result = client.send(:parse_categorization_response, response)

      expect(result[:category]).to eq('BILLING')
      expect(result[:confidence]).to eq(85)
      expect(result[:reason]).to eq('Commit modifies billing-related files')
    end

    it 'defaults confidence to 50 if missing' do
      response = <<~RESPONSE
        CATEGORY: SECURITY
        REASON: Updates security policies
      RESPONSE

      result = client.send(:parse_categorization_response, response)

      expect(result[:category]).to eq('SECURITY')
      expect(result[:confidence]).to eq(50)
    end

    it 'defaults reason if missing' do
      response = <<~RESPONSE
        CATEGORY: API
        CONFIDENCE: 90
      RESPONSE

      result = client.send(:parse_categorization_response, response)

      expect(result[:reason]).to eq('No reason provided')
    end

    it 'clamps confidence to 0-100 range' do
      response = <<~RESPONSE
        CATEGORY: TEST
        CONFIDENCE: 150
        REASON: Over limit
      RESPONSE

      result = client.send(:parse_categorization_response, response)
      expect(result[:confidence]).to eq(100)
    end

    it 'raises error if category is missing' do
      response = <<~RESPONSE
        CONFIDENCE: 90
        REASON: No category provided
      RESPONSE

      expect do
        client.send(:parse_categorization_response, response)
      end.to raise_error(LLM::BaseClient::APIError, /Could not extract category/)
    end

    it 'raises error if category is invalid (numeric)' do
      response = <<~RESPONSE
        CATEGORY: 2.58.0
        CONFIDENCE: 90
        REASON: Version number
      RESPONSE

      expect do
        client.send(:parse_categorization_response, response)
      end.to raise_error(LLM::BaseClient::APIError, /Invalid category/)
    end
  end

  describe '#build_categorization_prompt' do
    let(:commit_data) do
      {
        hash: 'abc123',
        subject: 'Fix payment processing bug',
        files: ['app/services/billing/payment_processor.rb', 'spec/services/billing/payment_processor_spec.rb']
      }
    end

    let(:existing_categories) { %w[BILLING CS SECURITY API] }

    it 'includes commit details' do
      prompt = client.send(:build_categorization_prompt, commit_data, existing_categories)

      expect(prompt).to include('Fix payment processing bug')
      expect(prompt).to include('abc123')
    end

    it 'includes file paths' do
      prompt = client.send(:build_categorization_prompt, commit_data, existing_categories)

      expect(prompt).to include('app/services/billing/payment_processor.rb')
      expect(prompt).to include('spec/services/billing/payment_processor_spec.rb')
    end

    it 'includes existing categories' do
      prompt = client.send(:build_categorization_prompt, commit_data, existing_categories)

      expect(prompt).to include('BILLING, CS, SECURITY, API')
    end

    it 'handles commits without files' do
      commit_without_files = commit_data.dup
      commit_without_files[:files] = []

      prompt = client.send(:build_categorization_prompt, commit_without_files, existing_categories)

      expect(prompt).to include('(not available)')
    end

    it 'handles empty category list' do
      prompt = client.send(:build_categorization_prompt, commit_data, [])

      expect(prompt).to include('none yet')
    end

    it 'includes validation instructions' do
      prompt = client.send(:build_categorization_prompt, commit_data, existing_categories)

      expect(prompt).to include('must start with a LETTER')
      expect(prompt).to include('AVOID: Version numbers')
      expect(prompt).to include('issue numbers')
    end
  end

  describe '#with_retry' do
    it 'executes block successfully on first try' do
      result = client.send(:with_retry) { 'success' }
      expect(result).to eq('success')
    end

    it 'retries on failure' do
      attempts = 0
      result = client.send(:with_retry) do
        attempts += 1
        attempts < 3 ? raise('temporary error') : 'success'
      end

      expect(result).to eq('success')
      expect(attempts).to eq(3)
    end

    it 'raises APIError after max retries' do
      expect do
        client.send(:with_retry) { raise StandardError, 'persistent error' }
      end.to raise_error(LLM::BaseClient::APIError, /persistent error/)
    end

    it 'raises TimeoutError on timeout' do
      expect do
        client.send(:with_retry) { sleep(client.timeout + 1) }
      end.to raise_error(LLM::BaseClient::TimeoutError)
    end
  end
end
