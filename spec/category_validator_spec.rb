# frozen_string_literal: true

require 'spec_helper'
require_relative '../lib/category_validator'

RSpec.describe CategoryValidator do
  describe '.valid_category?' do
    context 'with PREVENT_NUMERIC_CATEGORIES enabled (default)' do
      before do
        ENV['PREVENT_NUMERIC_CATEGORIES'] = 'true'
      end

      after do
        ENV.delete('PREVENT_NUMERIC_CATEGORIES')
      end

      describe 'valid categories' do
        it 'accepts simple uppercase category' do
          expect(described_class.valid_category?('BILLING')).to be true
        end

        it 'accepts multi-word category' do
          expect(described_class.valid_category?('API GATEWAY')).to be true
        end

        it 'accepts category with hyphen' do
          expect(described_class.valid_category?('E-COMMERCE')).to be true
        end

        it 'accepts category with underscore' do
          expect(described_class.valid_category?('USER_AUTH')).to be true
        end

        it 'accepts category with some numbers' do
          expect(described_class.valid_category?('I18N')).to be true
          expect(described_class.valid_category?('L10N')).to be true
          expect(described_class.valid_category?('OAUTH2')).to be true
        end

        it 'accepts mixed case category' do
          expect(described_class.valid_category?('ApiGateway')).to be true
        end

        it 'accepts category at minimum length' do
          expect(described_class.valid_category?('CS')).to be true
        end

        it 'accepts category at maximum length' do
          long_category = 'A' * 50
          expect(described_class.valid_category?(long_category)).to be true
        end
      end

      describe 'invalid categories' do
        it 'rejects nil' do
          expect(described_class.valid_category?(nil)).to be false
        end

        it 'rejects empty string' do
          expect(described_class.valid_category?('')).to be false
        end

        it 'rejects whitespace only' do
          expect(described_class.valid_category?('   ')).to be false
        end

        it 'rejects too short (1 char)' do
          expect(described_class.valid_category?('A')).to be false
        end

        it 'rejects too long (>50 chars)' do
          long_category = 'A' * 51
          expect(described_class.valid_category?(long_category)).to be false
        end

        it 'rejects categories without letters' do
          expect(described_class.valid_category?('123')).to be false
          expect(described_class.valid_category?('###')).to be false
          expect(described_class.valid_category?('...')).to be false
        end
      end

      describe 'numeric category rejection' do
        it 'rejects version numbers' do
          expect(described_class.valid_category?('2.26.0')).to be false
          expect(described_class.valid_category?('2.58.0')).to be false
          expect(described_class.valid_category?('1.2.3')).to be false
          expect(described_class.valid_category?('10.0.1')).to be false
        end

        it 'rejects issue numbers' do
          expect(described_class.valid_category?('#5930')).to be false
          expect(described_class.valid_category?('#6802')).to be false
          expect(described_class.valid_category?('#117')).to be false
          expect(described_class.valid_category?('#1')).to be false
        end

        it 'rejects purely numeric categories' do
          expect(described_class.valid_category?('2023')).to be false
          expect(described_class.valid_category?('123')).to be false
          expect(described_class.valid_category?('42')).to be false
        end

        it 'accepts categories starting with numbers if they have letters' do
          expect(described_class.valid_category?('2FA')).to be true
          expect(described_class.valid_category?('3D_RENDERING')).to be true
          expect(described_class.valid_category?('3D')).to be true
        end

        it 'rejects categories starting with # symbol' do
          expect(described_class.valid_category?('#HASHTAG')).to be false
          expect(described_class.valid_category?('#TAG')).to be false
        end

        it 'rejects categories with >50% digits' do
          expect(described_class.valid_category?('12345ABC')).to be false # 62.5% digits
          expect(described_class.valid_category?('1234AB')).to be false # 66% digits
        end

        it 'accepts categories with <=50% digits' do
          expect(described_class.valid_category?('ABC123')).to be true # 50% digits
          expect(described_class.valid_category?('I18N')).to be true # 25% digits
          expect(described_class.valid_category?('OAUTH2')).to be true # 16% digits
          expect(described_class.valid_category?('HTTP2')).to be true # 20% digits
        end
      end

      describe 'edge cases' do
        it 'rejects categories that look like dates' do
          expect(described_class.valid_category?('2023-12-25')).to be false
          expect(described_class.valid_category?('2024.01.15')).to be false
        end

        it 'accepts legitimate technical categories with numbers' do
          expect(described_class.valid_category?('OAUTH2')).to be true
          expect(described_class.valid_category?('HTTP2')).to be true
          expect(described_class.valid_category?('BASE64')).to be true
        end

        it 'accepts categories with special meaning' do
          expect(described_class.valid_category?('A/B TESTING')).to be true
          expect(described_class.valid_category?('L10N')).to be true
        end
      end
    end

    context 'with PREVENT_NUMERIC_CATEGORIES disabled' do
      before do
        ENV['PREVENT_NUMERIC_CATEGORIES'] = 'false'
      end

      after do
        ENV.delete('PREVENT_NUMERIC_CATEGORIES')
      end

      it 'allows version numbers' do
        expect(described_class.valid_category?('2.26.0')).to be false # Still no letters
      end

      it 'allows issue numbers' do
        expect(described_class.valid_category?('#6802')).to be false # Still no letters
      end

      it 'allows categories starting with numbers if they have letters' do
        expect(described_class.valid_category?('2FA')).to be true
      end

      it 'still requires at least one letter' do
        expect(described_class.valid_category?('123')).to be false
        expect(described_class.valid_category?('2.58.0')).to be false
      end

      it 'allows categories with many digits' do
        expect(described_class.valid_category?('12345ABC')).to be true
      end
    end
  end

  describe '.rejection_reason' do
    before do
      ENV['PREVENT_NUMERIC_CATEGORIES'] = 'true'
    end

    after do
      ENV.delete('PREVENT_NUMERIC_CATEGORIES')
    end

    it 'returns reason for nil' do
      expect(described_class.rejection_reason(nil)).to eq('nil or empty')
    end

    it 'returns reason for empty' do
      expect(described_class.rejection_reason('')).to eq('nil or empty')
    end

    it 'returns reason for too short' do
      expect(described_class.rejection_reason('A')).to eq('too short (<2 chars)')
    end

    it 'returns reason for too long' do
      long = 'A' * 51
      expect(described_class.rejection_reason(long)).to eq('too long (>50 chars)')
    end

    it 'returns valid for categories starting with numbers but having letters' do
      expect(described_class.rejection_reason('2FA')).to eq('valid')
    end

    it 'returns reason for purely numeric' do
      expect(described_class.rejection_reason('123')).to eq('purely numeric')
    end

    it 'returns reason for version number' do
      expect(described_class.rejection_reason('2.58.0')).to eq('looks like version number')
    end

    it 'returns reason for issue number' do
      expect(described_class.rejection_reason('#6802')).to eq('looks like issue number')
    end

    it 'returns reason for starting with #' do
      expect(described_class.rejection_reason('#HASHTAG')).to eq('starts with # symbol')
    end

    it 'returns reason for too many digits' do
      # 12345ABC = 62.5% digits
      expect(described_class.rejection_reason('12345ABC')).to eq('too many digits (>50%)')
    end

    it 'returns reason for too many digits when it starts with letter' do
      # AB1234 = 66% digits, starts with letter
      expect(described_class.rejection_reason('AB1234')).to eq('too many digits (>50%)')
    end

    it 'returns reason for no letters' do
      expect(described_class.rejection_reason('###')).to eq('starts with # symbol')
    end

    it 'returns valid for valid category' do
      expect(described_class.rejection_reason('BILLING')).to eq('valid')
    end
  end

  describe 'integration with pattern-based categorization' do
    context 'when extracting from commit subjects' do
      it 'rejects version number categories' do
        # These would be extracted but should be rejected
        expect(described_class.valid_category?('2.26.0')).to be false
        expect(described_class.valid_category?('2.58.0')).to be false
      end

      it 'rejects issue number categories' do
        expect(described_class.valid_category?('#5930')).to be false
        expect(described_class.valid_category?('#6802')).to be false
      end

      it 'accepts legitimate business categories' do
        expect(described_class.valid_category?('BILLING')).to be true
        expect(described_class.valid_category?('CS')).to be true
        expect(described_class.valid_category?('SECURITY')).to be true
        expect(described_class.valid_category?('API')).to be true
      end
    end
  end
end
