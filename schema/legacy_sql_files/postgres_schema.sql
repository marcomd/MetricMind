-- PostgreSQL Schema for Git Productivity Analytics
-- Version: 1.0
-- Description: Stores per-commit data from multiple git repositories

-- Drop existing tables (in correct order due to foreign keys)
DROP TABLE IF EXISTS commits CASCADE;
DROP TABLE IF EXISTS repositories CASCADE;

-- Repositories table
CREATE TABLE repositories (
    id SERIAL PRIMARY KEY,
    name VARCHAR(255) NOT NULL UNIQUE,
    url TEXT,
    description TEXT,
    last_extracted_at TIMESTAMP WITH TIME ZONE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX idx_repositories_name ON repositories(name);

-- Commits table (per-commit granularity)
CREATE TABLE commits (
    id SERIAL PRIMARY KEY,
    repository_id INTEGER NOT NULL REFERENCES repositories(id) ON DELETE CASCADE,
    hash VARCHAR(40) NOT NULL,
    commit_date TIMESTAMP WITH TIME ZONE NOT NULL,
    author_name VARCHAR(255) NOT NULL,
    author_email VARCHAR(255) NOT NULL,
    subject TEXT NOT NULL,
    lines_added INTEGER NOT NULL DEFAULT 0,
    lines_deleted INTEGER NOT NULL DEFAULT 0,
    files_changed INTEGER NOT NULL DEFAULT 0,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,

    -- Ensure unique commits per repository
    CONSTRAINT unique_commit_per_repo UNIQUE (repository_id, hash)
);

-- Indexes for efficient querying
CREATE INDEX idx_commits_repository_id ON commits(repository_id);
CREATE INDEX idx_commits_commit_date ON commits(commit_date);
CREATE INDEX idx_commits_author_email ON commits(author_email);
CREATE INDEX idx_commits_author_name ON commits(author_name);
CREATE INDEX idx_commits_repo_date ON commits(repository_id, commit_date);
CREATE INDEX idx_commits_hash ON commits(hash);

-- Composite index for common queries (repository + date range + author)
CREATE INDEX idx_commits_repo_date_author ON commits(repository_id, commit_date, author_email);

-- Comments for documentation
COMMENT ON TABLE repositories IS 'Stores metadata about git repositories being tracked';
COMMENT ON TABLE commits IS 'Stores per-commit data including lines changed and author information';

COMMENT ON COLUMN commits.hash IS 'Git commit SHA hash (40 characters)';
COMMENT ON COLUMN commits.commit_date IS 'Date when the commit was authored';
COMMENT ON COLUMN commits.author_name IS 'Author name from git commit';
COMMENT ON COLUMN commits.author_email IS 'Author email from git commit (used for unique identification)';
COMMENT ON COLUMN commits.subject IS 'First line of commit message';
COMMENT ON COLUMN commits.lines_added IS 'Total lines added in this commit (excluding binary files)';
COMMENT ON COLUMN commits.lines_deleted IS 'Total lines deleted in this commit (excluding binary files)';
COMMENT ON COLUMN commits.files_changed IS 'Number of files modified in this commit';
