# Dashboard Schema Differences

This document tracks schema differences between the **MetricMind Extractor** (this project) and the **Dashboard Project**.

## Overview

The MetricMind Extractor creates and manages the base database schema. The Dashboard Project adds additional tables and columns for its web application features (authentication, session management, etc.).

**Important**: Both projects should use the same migration system (Sequel) to ensure consistency and prevent conflicts.

## Schema Differences

### Users Table

The `users` table was created in migration `002_add_users_and_oauth.sql` in the extractor project. The dashboard project has added additional columns for GitHub and GitLab OAuth authentication.

**Extractor Schema** (base):
```sql
CREATE TABLE users (
  id SERIAL PRIMARY KEY,
  email VARCHAR(255) NOT NULL UNIQUE,
  name VARCHAR(255),
  avatar_url TEXT,
  google_id VARCHAR(255) UNIQUE,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
  last_sign_in_at TIMESTAMP WITH TIME ZONE
);
```

**Dashboard Additional Columns**:
```sql
-- GitHub OAuth support
ALTER TABLE users ADD COLUMN github_id VARCHAR(255) UNIQUE;
ALTER TABLE users ADD COLUMN github_username VARCHAR(255);

-- GitLab OAuth support
ALTER TABLE users ADD COLUMN gitlab_id VARCHAR(255) UNIQUE;
ALTER TABLE users ADD COLUMN gitlab_username VARCHAR(255);

-- Additional metadata
ALTER TABLE users ADD COLUMN updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP;
```

### Dashboard-Only Tables

The following tables exist only in the Dashboard database and are not managed by the extractor:

1. **sessions** - Web session management
   ```sql
   CREATE TABLE sessions (
     id SERIAL PRIMARY KEY,
     user_id INTEGER REFERENCES users(id) ON DELETE CASCADE,
     session_token VARCHAR(255) NOT NULL UNIQUE,
     expires_at TIMESTAMP WITH TIME ZONE NOT NULL,
     created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
   );
   ```

2. **user_preferences** - User settings and preferences
   ```sql
   CREATE TABLE user_preferences (
     id SERIAL PRIMARY KEY,
     user_id INTEGER REFERENCES users(id) ON DELETE CASCADE,
     theme VARCHAR(50) DEFAULT 'light',
     notifications_enabled BOOLEAN DEFAULT true,
     created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
     updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
   );
   ```

## Synchronization Strategy

### Option 1: Dashboard Creates Its Own Migrations (CURRENT)

**Status**: ✓ Chosen approach

The dashboard project maintains its own migrations for dashboard-specific features:
- Dashboard runs its own `db_migrate.rb` against the shared database
- Dashboard migrations are separate from extractor migrations
- Both projects use the same `schema_migrations` table (Sequel tracks migrations by filename)
- No conflicts as long as migration timestamps don't overlap

**Pros:**
- Clear separation of concerns
- Each project owns its schema changes
- Independent deployment and testing

**Cons:**
- Need to manually ensure migration filenames don't collide (unlikely with timestamps)
- Must document differences (this file)

**How to implement:**
1. Dashboard project should use the same Sequel migration system
2. Create dashboard migrations with: `./scripts/db_migrate_new.rb add_github_auth_to_users`
3. Apply dashboard migrations: `./scripts/db_migrate.rb` (in dashboard project)
4. Both projects' migrations coexist in `schema_migrations` table

### Option 2: Extractor Includes Dashboard Migrations (Alternative)

**Status**: ✗ Not chosen (but available if needed)

All migrations live in the extractor project, including dashboard-specific ones:
- Single source of truth for all schema changes
- Extractor migrations include dashboard tables/columns
- Dashboard project uses read-only schema

**Pros:**
- Single migration history
- Easier to track overall schema evolution

**Cons:**
- Extractor needs to know about dashboard features
- Tight coupling between projects
- Dashboard can't evolve schema independently

## Current Status

**Extractor Project** (this project):
- ✓ Sequel migration system implemented
- ✓ Base schema and views managed here
- ✓ Migration scripts: `db_migrate.rb`, `db_rollback.rb`, `db_migrate_status.rb`, `db_migrate_new.rb`

**Dashboard Project** (separate):
- ⚠ Needs Sequel migration system implementation (use extractor scripts as template)
- ⚠ Create migrations for existing dashboard schema changes
- ⚠ Document migration workflow in dashboard README

## Recommendations

### For Dashboard Team

1. **Implement Sequel migrations in dashboard project**:
   ```bash
   # Copy migration scripts from extractor project
   cp -r extractor/scripts/db_*.rb dashboard/scripts/
   cp extractor/lib/sequel_connection.rb dashboard/lib/

   # Update Gemfile
   gem 'sequel', '~> 5.75'
   bundle install
   ```

2. **Create migrations for existing dashboard changes**:
   ```bash
   # In dashboard project
   ./scripts/db_migrate_new.rb add_github_gitlab_auth_to_users
   ./scripts/db_migrate_new.rb create_sessions_table
   ./scripts/db_migrate_new.rb create_user_preferences_table
   ```

3. **Apply dashboard migrations**:
   ```bash
   # In dashboard project
   ./scripts/db_migrate.rb
   ```

4. **Check combined migration status**:
   ```bash
   # Should show both extractor and dashboard migrations
   ./scripts/db_migrate_status.rb
   ```

### Schema Change Workflow

**When extractor needs schema changes:**
1. Create migration in extractor project
2. Apply to extractor database
3. Document in this file if it affects dashboard

**When dashboard needs schema changes:**
1. Create migration in dashboard project
2. Apply to dashboard database
3. Document in this file

**When making changes to shared tables** (e.g., users, commits):
1. Discuss with both teams
2. Create migration in appropriate project (usually extractor for core tables)
3. Test on both projects
4. Document clearly

## Migration Naming Convention

To avoid conflicts, use descriptive names and rely on timestamps:

**Extractor migrations** (example):
- `20241108120000_add_commit_categorization.rb`
- `20241116143000_add_ai_categorization.rb`

**Dashboard migrations** (example):
- `20241121100000_add_github_auth_to_users.rb`
- `20241121100100_create_sessions_table.rb`

Timestamps naturally prevent collisions as long as migrations are created at different times.

## Testing

### Testing Schema Compatibility

Both projects should test against the combined schema:

```bash
# In extractor project
./scripts/db_migrate.rb
bundle exec rspec

# In dashboard project
./scripts/db_migrate.rb
# Run dashboard tests
```

### Rollback Testing

Test rollback scenarios for both projects:

```bash
# Test dashboard rollback doesn't break extractor
cd dashboard && ./scripts/db_rollback.rb
cd extractor && bundle exec rspec

# Test extractor rollback doesn't break dashboard
cd extractor && ./scripts/db_rollback.rb
cd dashboard && # run dashboard tests
```

## Questions?

If you need to synchronize schema changes or have questions about the migration strategy:
1. Check this document first
2. Review both projects' migration histories: `./scripts/db_migrate_status.rb`
3. Contact the extractor or dashboard team for coordination
