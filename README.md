# Supabase Archive Toolkit

Backup and restore Supabase projects for archiving. Perfect for pausing paid projects to avoid costs.

## What Gets Backed Up

| Component | Included |
|-----------|----------|
| Database schema (tables, views, functions, triggers) | Yes |
| Database data | Yes |
| RLS policies | Yes |
| Storage buckets & files | Yes |
| Bucket configurations (public/private, size limits) | Yes |
| Edge Functions | Manual (see below) |
| Auth users | No (security reasons) |

## Prerequisites

1. **PostgreSQL client tools**
   ```bash
   brew install postgresql
   ```

2. **Node.js** (v18+)
   ```bash
   brew install node
   ```

3. **Your Supabase credentials** (from Dashboard → Settings → API)

## Setup

1. Clone this repo or download the files

2. Install dependencies:
   ```bash
   npm install
   ```

3. Create your `.env` file:
   ```bash
   cp .env.example .env
   ```

4. Fill in your credentials in `.env`:
   ```
   SUPABASE_URL=https://your-project-ref.supabase.co
   SUPABASE_SERVICE_ROLE_KEY=your-service-role-key
   PROJECT_NAME=my-app
   DATABASE_URL=postgresql://postgres:[PASSWORD]@db.your-project-ref.supabase.co:5432/postgres
   ```

   Find DATABASE_URL at: Dashboard → Settings → Database → Connection string → URI

## Backup

```bash
chmod +x backup.sh
./backup.sh
```

This creates:
- `backups/PROJECT_NAME_TIMESTAMP/` - Folder with all backup files
- `backups/PROJECT_NAME_TIMESTAMP.tar.gz` - Compressed archive

### Backup Contents

```
backups/my-app_20240115_120000/
├── schema.sql          # Database structure
├── data.sql            # Database data
├── full_backup.sql     # Combined schema + data
├── metadata.json       # Backup info
└── storage/
    ├── buckets.json    # Bucket configurations
    ├── avatars/        # Files from 'avatars' bucket
    └── documents/      # Files from 'documents' bucket
```

## Restore

1. Create a new Supabase project at [supabase.com](https://supabase.com)

2. Update `.env` with the NEW project's credentials

3. Run restore:
   ```bash
   chmod +x restore.sh
   ./restore.sh backups/my-app_20240115_120000
   # or with archive:
   ./restore.sh backups/my-app_20240115_120000.tar.gz
   ```

4. Update your app's environment variables with the new Supabase URL and keys

## Lovable Integration

### Before Archiving

1. **Connect Lovable to GitHub** (if not already):
   - In Lovable: Click your project → Settings → GitHub → Connect
   - This saves your complete frontend code

2. **Note your Supabase integration**:
   - In Lovable: Settings → Supabase
   - Document any tables/functions you created through Lovable

### After Restoring

1. Create new Supabase project and run `./restore.sh`

2. Update Lovable:
   - Go to your Lovable project (from GitHub or lovable.dev)
   - Settings → Supabase → Update connection with new URL and keys

3. Redeploy your app

## Edge Functions

Edge Functions must be backed up manually:

```bash
# If you have the supabase CLI linked to your project:
supabase functions download <function-name> --project-ref <your-ref>

# Or copy from your local supabase/functions directory
```

To restore:
```bash
supabase functions deploy <function-name> --project-ref <new-project-ref>
```

## Complete Archive Checklist

- [ ] Run `./backup.sh`
- [ ] Verify backup archive was created
- [ ] Connect Lovable project to GitHub (if applicable)
- [ ] Download/backup Edge Functions (if any)
- [ ] Document any third-party integrations (Stripe, etc.)
- [ ] Store backup archive safely (cloud storage, external drive)
- [ ] Delete Supabase project to stop billing

## Restore Checklist

- [ ] Create new Supabase project (same region recommended)
- [ ] Update `.env` with new credentials
- [ ] Run `./restore.sh backups/your-backup`
- [ ] Deploy Edge Functions (if any)
- [ ] Update Lovable/app with new Supabase credentials
- [ ] Reconfigure third-party integrations
- [ ] Test application thoroughly

## Troubleshooting

### "permission denied" errors during restore
Some system schemas can't be modified. These errors can usually be ignored.

### Storage files not uploading
Check that your service role key has storage permissions.

### Missing tables after restore
Run the full backup restore instead of schema + data separately:
```bash
psql "$DATABASE_URL" -f backups/your-backup/full_backup.sql
```

## License

MIT
