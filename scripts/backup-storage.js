const { createClient } = require('@supabase/supabase-js');
const fs = require('fs-extra');
const path = require('path');
require('dotenv').config();

const supabaseUrl = process.env.SUPABASE_URL;
const supabaseKey = process.env.SUPABASE_SERVICE_ROLE_KEY;
const backupDir = process.env.BACKUP_DIR || 'backups/storage';

if (!supabaseUrl || !supabaseKey) {
    console.error('Error: SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY are required');
    process.exit(1);
}

const supabase = createClient(supabaseUrl, supabaseKey);

async function listAllFiles(bucket, folderPath = '') {
    const files = [];
    const { data, error } = await supabase.storage.from(bucket).list(folderPath, {
        limit: 1000,
        offset: 0,
    });

    if (error) {
        console.error(`Error listing files in ${bucket}/${folderPath}:`, error.message);
        return files;
    }

    for (const item of data || []) {
        const itemPath = folderPath ? `${folderPath}/${item.name}` : item.name;

        if (item.id === null) {
            // It's a folder, recurse
            const subFiles = await listAllFiles(bucket, itemPath);
            files.push(...subFiles);
        } else {
            // It's a file
            files.push(itemPath);
        }
    }

    return files;
}

async function downloadFile(bucket, filePath, localPath) {
    const { data, error } = await supabase.storage.from(bucket).download(filePath);

    if (error) {
        console.error(`Error downloading ${bucket}/${filePath}:`, error.message);
        return false;
    }

    await fs.ensureDir(path.dirname(localPath));
    const buffer = Buffer.from(await data.arrayBuffer());
    await fs.writeFile(localPath, buffer);
    return true;
}

async function backupStorage() {
    console.log('Fetching storage buckets...');

    const { data: buckets, error } = await supabase.storage.listBuckets();

    if (error) {
        console.error('Error listing buckets:', error.message);
        process.exit(1);
    }

    if (!buckets || buckets.length === 0) {
        console.log('No storage buckets found.');
        return;
    }

    const storageDir = path.join(backupDir, 'storage');
    await fs.ensureDir(storageDir);

    // Save bucket metadata
    const bucketMetadata = buckets.map(b => ({
        name: b.name,
        public: b.public,
        file_size_limit: b.file_size_limit,
        allowed_mime_types: b.allowed_mime_types
    }));

    await fs.writeJson(path.join(storageDir, 'buckets.json'), bucketMetadata, { spaces: 2 });
    console.log(`Found ${buckets.length} bucket(s): ${buckets.map(b => b.name).join(', ')}`);

    let totalFiles = 0;
    let downloadedFiles = 0;

    for (const bucket of buckets) {
        console.log(`\nProcessing bucket: ${bucket.name}`);
        const bucketDir = path.join(storageDir, bucket.name);
        await fs.ensureDir(bucketDir);

        const files = await listAllFiles(bucket.name);
        totalFiles += files.length;
        console.log(`  Found ${files.length} file(s)`);

        for (const filePath of files) {
            const localPath = path.join(bucketDir, filePath);
            const success = await downloadFile(bucket.name, filePath, localPath);
            if (success) {
                downloadedFiles++;
                process.stdout.write(`  Downloaded: ${filePath}\n`);
            }
        }
    }

    console.log(`\nStorage backup complete: ${downloadedFiles}/${totalFiles} files downloaded`);
}

backupStorage().catch(console.error);
