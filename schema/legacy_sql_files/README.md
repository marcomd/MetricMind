# Legacy SQL Files (Archived)

This directory contains the original SQL schema files that were used before migrating to the Sequel migration system.

## Migration to Sequel

As of **November 23, 2025**, all schema management has been unified into Sequel migrations located in `schema/migrations/`.

### Converted Files

These SQL files have been converted to timestamp-based migrations:

- `postgres_schema.sql` → `20251107000000_create_base_schema.rb`
- `postgres_views.sql` → `20251112080000_create_standard_views.rb`
- `category_views.sql` → `20251116000000_create_category_views.rb`
- `personal_views.sql` → `20251122000000_create_personal_views.rb`

### Why These Files Are Archived

**These files are NO LONGER USED** by the application. They are kept here for:
1. **Historical reference** - Understanding the evolution of the schema
2. **Documentation** - Quick reference for SQL syntax without opening Ruby files
3. **Rollback safety** - Backup in case migration conversion needs review

### Current Schema Management

**DO NOT edit these archived SQL files.** To make schema changes:

```bash
# Create a new migration
./scripts/db_migrate_new.rb your_migration_description

# Edit the generated file in schema/migrations/
# Run migrations
./scripts/db_migrate.rb
```

### For Existing Databases

If you have an existing database that was set up with these SQL files, the setup script will automatically detect this and seed the `schema_migrations` table to prevent re-execution of converted migrations.

No manual action is required - just run:
```bash
./scripts/setup.sh --database-only
```

### Removal

These files may be removed in a future version after confirming all databases have been successfully migrated to the new system. Until then, they serve as a safety net and reference.

---

**Last updated:** November 23, 2025
**Migration system:** Sequel 5.75+
**See also:** `../migrations/` for current schema definitions
