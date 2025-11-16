# frozen_string_literal: true

require 'spec_helper'
require_relative '../scripts/sync_commit_weights_from_categories'

RSpec.describe CommitWeightSynchronizer do
  let(:mock_conn) { instance_double(PG::Connection) }
  let(:synchronizer) { CommitWeightSynchronizer.new(dry_run: true) }

  before do
    allow(synchronizer).to receive(:connect_to_db).and_return(mock_conn)
    allow(mock_conn).to receive(:close)
  end

  describe '#initialize' do
    it 'initializes with default options' do
      sync = CommitWeightSynchronizer.new
      expect(sync).to be_a(CommitWeightSynchronizer)
    end

    it 'initializes with dry_run option' do
      sync = CommitWeightSynchronizer.new(dry_run: true)
      expect(sync.instance_variable_get(:@dry_run)).to be true
    end

    it 'initializes with repo filter' do
      sync = CommitWeightSynchronizer.new(repo: 'mater')
      expect(sync.instance_variable_get(:@repo_filter)).to eq('mater')
    end

    it 'initializes statistics hash' do
      stats = synchronizer.instance_variable_get(:@stats)
      expect(stats[:total_commits]).to eq(0)
      expect(stats[:updated_commits]).to eq(0)
      expect(stats[:skipped_reverted]).to eq(0)
      expect(stats[:categories_processed]).to eq(0)
    end
  end

  describe '#fetch_categories' do
    it 'fetches all categories with their weights' do
      categories = [
        { 'id' => '1', 'name' => 'BILLING', 'weight' => '100' },
        { 'id' => '2', 'name' => 'CS', 'weight' => '50' }
      ]

      result = instance_double(PG::Result, to_a: categories)
      expect(mock_conn).to receive(:exec).with(anything).and_return(result)

      fetched = synchronizer.send(:fetch_categories)
      expect(fetched).to eq(categories)
    end

    it 'returns empty array when no categories exist' do
      result = instance_double(PG::Result, to_a: [])
      expect(mock_conn).to receive(:exec).with(anything).and_return(result)

      fetched = synchronizer.send(:fetch_categories)
      expect(fetched).to be_empty
    end
  end

  describe '#process_category' do
    let(:category) { { 'id' => '1', 'name' => 'BILLING', 'weight' => '50' } }

    context 'when commits exist for category' do
      it 'updates category statistics' do
        count_result = instance_double(PG::Result,
                                       to_a: [{ 'total' => '10', 'non_reverted' => '8', 'reverted' => '2' }])
        allow(mock_conn).to receive(:exec_params).and_return(count_result)

        synchronizer.send(:process_category, category)

        stats = synchronizer.instance_variable_get(:@stats)
        expect(stats[:total_commits]).to eq(10)
        expect(stats[:skipped_reverted]).to eq(2)
      end

      it 'tracks per-category statistics' do
        count_result = instance_double(PG::Result,
                                       to_a: [{ 'total' => '10', 'non_reverted' => '8', 'reverted' => '2' }])
        allow(mock_conn).to receive(:exec_params).and_return(count_result)

        synchronizer.send(:process_category, category)

        category_stats = synchronizer.instance_variable_get(:@category_stats)
        expect(category_stats['BILLING']).to eq({
                                                   weight: 50,
                                                   commits: 8,
                                                   reverted_skipped: 2
                                                 })
      end
    end

    context 'when no non-reverted commits exist' do
      it 'skips update and does not track category stats' do
        count_result = instance_double(PG::Result,
                                       to_a: [{ 'total' => '5', 'non_reverted' => '0', 'reverted' => '5' }])
        allow(mock_conn).to receive(:exec_params).and_return(count_result)

        synchronizer.send(:process_category, category)

        category_stats = synchronizer.instance_variable_get(:@category_stats)
        expect(category_stats).not_to have_key('BILLING')
      end
    end
  end

  describe '#build_count_query' do
    context 'without repository filter' do
      it 'builds query for all repositories' do
        query = synchronizer.send(:build_count_query)
        expect(query).to include('WHERE c.category = $1')
        expect(query).not_to include('r.name = $1')
      end
    end

    context 'with repository filter' do
      let(:synchronizer_with_repo) { CommitWeightSynchronizer.new(dry_run: true, repo: 'mater') }

      before do
        allow(synchronizer_with_repo).to receive(:connect_to_db).and_return(mock_conn)
        allow(mock_conn).to receive(:close)
      end

      it 'builds query with repository filter' do
        query = synchronizer_with_repo.send(:build_count_query)
        expect(query).to include('r.name = $1')
        expect(query).to include('c.category = $2')
      end
    end
  end

  describe '#build_update_query' do
    context 'without repository filter' do
      it 'builds query for all repositories' do
        query = synchronizer.send(:build_update_query)
        expect(query).to include('SET weight = $1')
        expect(query).to include('c.category = $2')
        expect(query).to include('c.weight > 0')
        expect(query).not_to include('r.name = $1')
      end
    end

    context 'with repository filter' do
      let(:synchronizer_with_repo) { CommitWeightSynchronizer.new(dry_run: true, repo: 'mater') }

      before do
        allow(synchronizer_with_repo).to receive(:connect_to_db).and_return(mock_conn)
        allow(mock_conn).to receive(:close)
      end

      it 'builds query with repository filter' do
        query = synchronizer_with_repo.send(:build_update_query)
        expect(query).to include('r.name = $1')
        expect(query).to include('SET weight = $2')
        expect(query).to include('c.category = $3')
        expect(query).to include('c.weight > 0')
      end
    end

    it 'always includes weight > 0 condition to preserve reverted commits' do
      query = synchronizer.send(:build_update_query)
      expect(query).to include('c.weight > 0')
    end
  end

  describe '#update_commits_for_category' do
    context 'in live mode' do
      let(:live_synchronizer) { CommitWeightSynchronizer.new(dry_run: false) }

      before do
        allow(live_synchronizer).to receive(:connect_to_db).and_return(mock_conn)
        allow(mock_conn).to receive(:close)
      end

      it 'executes update query with correct parameters' do
        expect(mock_conn).to receive(:exec_params).with(anything, [50, 'BILLING'])

        live_synchronizer.send(:update_commits_for_category, 'BILLING', 50)
      end

      it 'handles database errors gracefully' do
        allow(mock_conn).to receive(:exec_params).and_raise(PG::Error.new('Connection lost'))

        expect do
          live_synchronizer.send(:update_commits_for_category, 'BILLING', 50)
        end.not_to raise_error
      end
    end
  end

  describe 'dry run mode' do
    it 'does not execute database updates' do
      allow(mock_conn).to receive(:exec).and_return(
        instance_double(PG::Result, to_a: [])
      )

      expect(mock_conn).not_to receive(:exec_params).with(/UPDATE/, anything)

      synchronizer.run
    end

    it 'displays preview messages' do
      categories = [{ 'id' => '1', 'name' => 'BILLING', 'weight' => '50' }]
      count_result = instance_double(PG::Result,
                                     to_a: [{ 'total' => '10', 'non_reverted' => '8', 'reverted' => '2' }])

      allow(mock_conn).to receive(:exec).and_return(
        instance_double(PG::Result, to_a: categories)
      )
      allow(mock_conn).to receive(:exec_params).and_return(count_result)

      expect do
        synchronizer.run
      end.to output(/DRY RUN/).to_stdout
    end
  end

  describe 'weight preservation for reverted commits' do
    it 'only updates commits with weight > 0' do
      query = synchronizer.send(:build_update_query)
      expect(query).to include('c.weight > 0')
    end

    it 'counts reverted commits separately' do
      category = { 'id' => '1', 'name' => 'BILLING', 'weight' => '50' }
      count_result = instance_double(PG::Result,
                                     to_a: [{ 'total' => '10', 'non_reverted' => '7', 'reverted' => '3' }])
      allow(mock_conn).to receive(:exec_params).and_return(count_result)

      synchronizer.send(:process_category, category)

      stats = synchronizer.instance_variable_get(:@stats)
      expect(stats[:skipped_reverted]).to eq(3)
    end
  end

  describe '#print_summary' do
    it 'prints summary without errors' do
      synchronizer.instance_variable_set(:@stats, {
                                           total_commits: 100,
                                           updated_commits: 80,
                                           skipped_reverted: 20,
                                           categories_processed: 5
                                         })

      synchronizer.instance_variable_set(:@category_stats, {
                                           'BILLING' => { weight: 50, commits: 30, reverted_skipped: 5 },
                                           'CS' => { weight: 100, commits: 50, reverted_skipped: 15 }
                                         })

      expect do
        synchronizer.send(:print_summary)
      end.to output(/SUMMARY/).to_stdout
    end

    it 'includes per-category breakdown' do
      synchronizer.instance_variable_set(:@category_stats, {
                                           'BILLING' => { weight: 50, commits: 30, reverted_skipped: 5 }
                                         })

      expect do
        synchronizer.send(:print_summary)
      end.to output(/BILLING/).to_stdout
    end

    it 'sorts categories by commit count descending' do
      synchronizer.instance_variable_set(:@category_stats, {
                                           'CS' => { weight: 100, commits: 50, reverted_skipped: 0 },
                                           'BILLING' => { weight: 50, commits: 30, reverted_skipped: 0 },
                                           'INFRA' => { weight: 75, commits: 40, reverted_skipped: 0 }
                                         })

      output = capture_stdout { synchronizer.send(:print_summary) }

      # CS (50 commits) should appear before INFRA (40 commits) should appear before BILLING (30 commits)
      cs_position = output.index('CS')
      infra_position = output.index('INFRA')
      billing_position = output.index('BILLING')

      expect(cs_position).to be < infra_position
      expect(infra_position).to be < billing_position
    end
  end

  describe 'error handling' do
    it 'handles database connection errors' do
      allow(PG).to receive(:connect).and_raise(PG::Error.new('Connection failed'))

      expect do
        CommitWeightSynchronizer.new.run
      end.to raise_error(SystemExit)
    end

    it 'closes database connection even on error' do
      allow(mock_conn).to receive(:exec).and_raise(StandardError.new('Unexpected error'))
      expect(mock_conn).to receive(:close)

      expect do
        synchronizer.run
      end.to raise_error(StandardError)
    end
  end

  # Helper method to capture stdout
  def capture_stdout
    original_stdout = $stdout
    $stdout = StringIO.new
    yield
    $stdout.string
  ensure
    $stdout = original_stdout
  end
end
