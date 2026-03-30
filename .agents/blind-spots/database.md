# Domain: Database & Data Access

Keywords: database, DB, SQL, query, migration, schema, index, transaction, Supabase, Prisma, Drizzle, PostgreSQL, MySQL, SQLite, RLS, row level security

lastReviewed: 2026-03-29

## Pitfall: N+1 Query Pattern

**Trigger:** Fetching related records (e.g., users with their posts, orders with items)
**Common mistake:** Fetching parent records, then looping to fetch children one by one
**Correct approach:** Use eager loading (JOIN, include), batch queries (WHERE id IN (...)), or dataloader patterns. Detect in code review by looking for queries inside loops.

## Pitfall: Missing Indexes on Foreign Keys

**Trigger:** Creating new tables with foreign key relationships
**Common mistake:** Assuming the database auto-creates indexes on foreign keys (PostgreSQL does NOT)
**Correct approach:** Always create indexes on foreign key columns explicitly. Without them, JOINs and cascade deletes become full table scans.

## Pitfall: Migration Without Rollback Plan

**Trigger:** Creating database migrations that modify existing data or drop columns
**Common mistake:** Destructive migrations (DROP COLUMN, data transformation) with no way to reverse
**Correct approach:** Write both `up` and `down` migrations. For destructive changes, use a two-phase approach: (1) add new column, migrate data, (2) drop old column in a later migration after verification. Never drop and recreate in one step.

## Pitfall: Transaction Scope Too Wide

**Trigger:** Operations that combine database writes with external API calls
**Common mistake:** Wrapping DB writes + API calls in a single transaction (API timeout = DB lock held)
**Correct approach:** Keep transactions as short as possible. Do external API calls outside the transaction. Use eventual consistency patterns (outbox, saga) for operations spanning DB + external services.

## Pitfall: Supabase RLS Bypass via Service Role Key

**Trigger:** Using Supabase with Row Level Security
**Common mistake:** Using the `service_role` key in client-side code or API routes without re-applying RLS logic
**Correct approach:** Use `anon` key for client-side. If `service_role` is needed server-side, always add explicit WHERE clauses matching the RLS policy logic. Test that RLS policies work by querying as the `anon` role.

## Pitfall: Soft Delete Leaks

**Trigger:** Implementing soft delete (deleted_at column)
**Common mistake:** Forgetting to add `WHERE deleted_at IS NULL` to all queries, leaking "deleted" records
**Correct approach:** Use global query filters/scopes (Prisma middleware, Drizzle where clauses, database views) to exclude soft-deleted records by default. Add explicit `withDeleted` scope for admin queries.

## Pitfall: ENUM Migration Trap

**Trigger:** Adding values to a PostgreSQL ENUM type
**Common mistake:** Using ALTER TYPE ... ADD VALUE inside a transaction (PostgreSQL doesn't allow this)
**Correct approach:** Run ALTER TYPE outside a transaction, or use a text column with CHECK constraint instead of ENUM (more migration-friendly).
