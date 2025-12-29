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

async function getAllFiles(dir, baseDir = dir) {
    const files = [];
    const items = await fs.readdir(dir, { withFileTypes: true });

    for (const item of items) {
        const fullPath = path.join(dir, item.name);
        if (item.isDirectory()) {
            const subFiles = await getAllFiles(fullPath, baseDir);
            files.push(...subFiles);
        } else if (item.name !== 'buckets.json') {
            const relativePath = path.relative(baseDir, fullPath);
            files.push({ fullPath, relativePath });
        }
    }

    return files;
}

async function restoreStorage() {
    const storageDir = path.join(backupDir, 'storage');

    if (!await fs.pathExists(storageDir)) {
        console.log('No storage backup found at:', storageDir);
        return;
    }

    // Load bucket metadata
    const bucketsFile = path.join(storageDir, 'buckets.json');
    let bucketMetadata = [];

    if (await fs.pathExists(bucketsFile)) {
        bucketMetadata = await fs.readJson(bucketsFile);
    }

    // Get list of backed up buckets (directories in storage folder)
    const items = await fs.readdir(storageDir, { withFileTypes: true });
    const bucketDirs = items.filter(i => i.isDirectory()).map(i => i.name);

    console.log(`Found ${bucketDirs.length} bucket(s) to restore: ${bucketDirs.join(', ')}`);

    let totalFiles = 0;
    let uploadedFiles = 0;

    for (const bucketName of bucketDirs) {
        console.log(`\nRestoring bucket: ${bucketName}`);

        // Find bucket config from metadata
        const bucketConfig = bucketMetadata.find(b => b.name === bucketName) || { public: false };

        // Check if bucket exists, create if not
        const { data: existingBuckets } = await supabase.storage.listBuckets();
        const bucketExists = existingBuckets?.some(b => b.name === bucketName);

        if (!bucketExists) {
            console.log(`  Creating bucket: ${bucketName} (public: ${bucketConfig.public})`);
            const { error: createError } = await supabase.storage.createBucket(bucketName, {
                public: bucketConfig.public,
                fileSizeLimit: bucketConfig.file_size_limit,
                allowedMimeTypes: bucketConfig.allowed_mime_types
            });

            if (createError) {
                console.error(`  Error creating bucket ${bucketName}:`, createError.message);
                continue;
            }
        } else {
            console.log(`  Bucket already exists: ${bucketName}`);
        }

        // Get all files in this bucket's backup
        const bucketDir = path.join(storageDir, bucketName);
        const files = await getAllFiles(bucketDir);
        totalFiles += files.length;

        console.log(`  Found ${files.length} file(s) to upload`);

        for (const { fullPath, relativePath } of files) {
            const fileContent = await fs.readFile(fullPath);
            const contentType = getContentType(relativePath);

            const { error: uploadError } = await supabase.storage
                .from(bucketName)
                .upload(relativePath, fileContent, {
                    contentType,
                    upsert: true
                });

            if (uploadError) {
                console.error(`  Error uploading ${relativePath}:`, uploadError.message);
            } else {
                uploadedFiles++;
                console.log(`  Uploaded: ${relativePath}`);
            }
        }
    }

    console.log(`\nStorage restore complete: ${uploadedFiles}/${totalFiles} files uploaded`);
}

function getContentType(filename) {
    const ext = path.extname(filename).toLowerCase();
    const mimeTypes = {
        '.jpg': 'image/jpeg',
        '.jpeg': 'image/jpeg',
        '.png': 'image/png',
        '.gif': 'image/gif',
        '.webp': 'image/webp',
        '.svg': 'image/svg+xml',
        '.pdf': 'application/pdf',
        '.json': 'application/json',
        '.txt': 'text/plain',
        '.html': 'text/html',
        '.css': 'text/css',
        '.js': 'application/javascript',
        '.mp4': 'video/mp4',
        '.mp3': 'audio/mpeg',
        '.wav': 'audio/wav',
        '.zip': 'application/zip',
    };
    return mimeTypes[ext] || 'application/octet-stream';
}

restoreStorage().catch(console.error);
