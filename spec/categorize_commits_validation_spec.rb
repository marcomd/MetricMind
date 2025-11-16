# frozen_string_literal: true

require 'spec_helper'
require_relative '../scripts/categorize_commits'

RSpec.describe CommitCategorizer, '#extract_category with validation' do
  let(:categorizer) { CommitCategorizer.new(dry_run: true) }

  before do
    ENV['PREVENT_NUMERIC_CATEGORIES'] = 'true'
  end

  after do
    ENV.delete('PREVENT_NUMERIC_CATEGORIES')
  end

  describe 'version number rejection' do
    it 'rejects version numbers from pipe delimiter' do
      result = categorizer.send(:extract_category, '2.26.0 | Release notes')
      expect(result).to be_nil
    end

    it 'rejects version numbers from square brackets' do
      result = categorizer.send(:extract_category, '[2.58.0] Release changes')
      expect(result).to be_nil
    end

    it 'rejects version numbers as first word' do
      result = categorizer.send(:extract_category, '2.26.0 RELEASE')
      expect(result).to be_nil
    end
  end

  describe 'issue number rejection' do
    it 'rejects issue numbers from pipe delimiter' do
      result = categorizer.send(:extract_category, '#5930 | Fix bug')
      expect(result).to be_nil
    end

    it 'rejects issue numbers from square brackets' do
      result = categorizer.send(:extract_category, '[#6802] Update feature')
      expect(result).to be_nil
    end

    it 'rejects issue numbers as first word' do
      result = categorizer.send(:extract_category, '#117 FIX')
      expect(result).to be_nil
    end
  end

  describe 'valid category extraction' do
    it 'accepts valid category from pipe delimiter' do
      result = categorizer.send(:extract_category, 'BILLING | Fix payment processor')
      expect(result).to eq('BILLING')
    end

    it 'accepts valid category from square brackets' do
      result = categorizer.send(:extract_category, '[CS] Update widget')
      expect(result).to eq('CS')
    end

    it 'accepts valid category as first word' do
      result = categorizer.send(:extract_category, 'SECURITY Fix vulnerability')
      expect(result).to eq('SECURITY')
    end

    it 'accepts category with numbers if valid' do
      result = categorizer.send(:extract_category, 'I18N | Add translations')
      expect(result).to eq('I18N')
    end
  end

  describe 'statistics tracking' do
    let(:mock_conn) { instance_double(PG::Connection) }

    before do
      allow(categorizer).to receive(:connect_to_db).and_return(mock_conn)
      allow(mock_conn).to receive(:close)
    end

    it 'increments rejected_invalid counter when category is invalid' do
      # Call extract_category with invalid category
      categorizer.send(:extract_category, '2.26.0 | Release')

      # Check that the stat was incremented
      expect(categorizer.instance_variable_get(:@stats)[:rejected_invalid]).to eq(1)
    end

    it 'does not increment rejected_invalid for valid categories' do
      categorizer.send(:extract_category, 'BILLING | Fix')
      expect(categorizer.instance_variable_get(:@stats)[:rejected_invalid]).to eq(0)
    end

    it 'tracks multiple rejections' do
      categorizer.send(:extract_category, '2.26.0 | Release')
      categorizer.send(:extract_category, '#5930 | Fix')
      categorizer.send(:extract_category, '2.58.0 | Update')

      expect(categorizer.instance_variable_get(:@stats)[:rejected_invalid]).to eq(3)
    end
  end

  describe 'categories starting with numbers' do
    it 'accepts 2FA-style categories' do
      result = categorizer.send(:extract_category, '2FA | Two-factor auth')
      expect(result).to eq('2FA')
    end

    it 'accepts 3D-style categories' do
      result = categorizer.send(:extract_category, '[3D] Rendering update')
      expect(result).to eq('3D')
    end

    it 'still rejects version numbers' do
      result = categorizer.send(:extract_category, '2.26.0 | Release')
      expect(result).to be_nil
    end

    it 'still rejects purely numeric' do
      result = categorizer.send(:extract_category, '2023 | Year update')
      expect(result).to be_nil
    end
  end

  describe 'with PREVENT_NUMERIC_CATEGORIES disabled' do
    before do
      ENV['PREVENT_NUMERIC_CATEGORIES'] = 'false'
    end

    it 'still rejects purely numeric (no letters)' do
      result = categorizer.send(:extract_category, '2.26.0 | Release')
      expect(result).to be_nil # No letters, still invalid
    end

    it 'allows categories starting with numbers if they have letters' do
      result = categorizer.send(:extract_category, '2FA | Setup')
      expect(result).to eq('2FA')
    end
  end

  describe 'edge cases' do
    it 'handles empty subject' do
      result = categorizer.send(:extract_category, '')
      expect(result).to be_nil
    end

    it 'handles nil subject' do
      result = categorizer.send(:extract_category, nil)
      expect(result).to be_nil
    end

    it 'handles subject with only whitespace' do
      result = categorizer.send(:extract_category, '   ')
      expect(result).to be_nil
    end

    it 'handles malformed patterns' do
      result = categorizer.send(:extract_category, '| No category before pipe')
      expect(result).to be_nil
    end

    it 'handles empty brackets' do
      result = categorizer.send(:extract_category, '[] Fix')
      expect(result).to be_nil
    end
  end
end
