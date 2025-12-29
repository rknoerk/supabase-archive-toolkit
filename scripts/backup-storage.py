#!/usr/bin/env python3
import os
import json
import urllib.request
import urllib.error
from pathlib import Path

# Load environment variables from .env file
def load_env():
    env_path = Path(__file__).parent.parent / '.env'
    env_vars = {}
    if env_path.exists():
        with open(env_path) as f:
            for line in f:
                line = line.strip()
                if line and not line.startswith('#') and '=' in line:
                    key, value = line.split('=', 1)
                    env_vars[key] = value
                    os.environ[key] = value
    return env_vars

load_env()

SUPABASE_URL = os.environ.get('SUPABASE_URL')
SUPABASE_KEY = os.environ.get('SUPABASE_SERVICE_ROLE_KEY')
BACKUP_DIR = os.environ.get('BACKUP_DIR', 'backups/storage')

if not SUPABASE_URL or not SUPABASE_KEY:
    print('Error: SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY are required')
    exit(1)

def api_request(endpoint, method='GET'):
    url = f"{SUPABASE_URL}/storage/v1/{endpoint}"
    req = urllib.request.Request(url, method=method)
    req.add_header('Authorization', f'Bearer {SUPABASE_KEY}')
    req.add_header('apikey', SUPABASE_KEY)

    try:
        with urllib.request.urlopen(req) as response:
            return json.loads(response.read().decode())
    except urllib.error.HTTPError as e:
        print(f"API Error: {e.code} - {e.read().decode()}")
        return None

def download_file(bucket, file_path, local_path):
    url = f"{SUPABASE_URL}/storage/v1/object/{bucket}/{file_path}"
    req = urllib.request.Request(url)
    req.add_header('Authorization', f'Bearer {SUPABASE_KEY}')
    req.add_header('apikey', SUPABASE_KEY)

    try:
        with urllib.request.urlopen(req) as response:
            Path(local_path).parent.mkdir(parents=True, exist_ok=True)
            with open(local_path, 'wb') as f:
                f.write(response.read())
            return True
    except urllib.error.HTTPError as e:
        print(f"  Error downloading {file_path}: {e.code}")
        return False

def list_files(bucket, folder=''):
    endpoint = f"object/list/{bucket}"
    url = f"{SUPABASE_URL}/storage/v1/{endpoint}"

    data = json.dumps({
        "prefix": folder,
        "limit": 1000,
        "offset": 0
    }).encode()

    req = urllib.request.Request(url, data=data, method='POST')
    req.add_header('Authorization', f'Bearer {SUPABASE_KEY}')
    req.add_header('apikey', SUPABASE_KEY)
    req.add_header('Content-Type', 'application/json')

    try:
        with urllib.request.urlopen(req) as response:
            return json.loads(response.read().decode())
    except urllib.error.HTTPError as e:
        print(f"  Error listing {bucket}/{folder}: {e.code}")
        return []

def list_all_files(bucket, folder=''):
    files = []
    items = list_files(bucket, folder)

    for item in items or []:
        item_path = f"{folder}/{item['name']}" if folder else item['name']

        if item.get('id') is None:
            # It's a folder
            sub_files = list_all_files(bucket, item_path)
            files.extend(sub_files)
        else:
            files.append(item_path)

    return files

def backup_storage():
    print('Fetching storage buckets...')
    buckets = api_request('bucket')

    if not buckets:
        print('No storage buckets found or error fetching buckets.')
        return

    storage_dir = Path(BACKUP_DIR) / 'storage'
    storage_dir.mkdir(parents=True, exist_ok=True)

    # Save bucket metadata
    bucket_metadata = [{
        'name': b['name'],
        'public': b.get('public', False),
        'file_size_limit': b.get('file_size_limit'),
        'allowed_mime_types': b.get('allowed_mime_types')
    } for b in buckets]

    with open(storage_dir / 'buckets.json', 'w') as f:
        json.dump(bucket_metadata, f, indent=2)

    print(f"Found {len(buckets)} bucket(s): {', '.join(b['name'] for b in buckets)}")

    total_files = 0
    downloaded_files = 0

    for bucket in buckets:
        bucket_name = bucket['name']
        print(f"\nProcessing bucket: {bucket_name}")

        bucket_dir = storage_dir / bucket_name
        bucket_dir.mkdir(parents=True, exist_ok=True)

        files = list_all_files(bucket_name)
        total_files += len(files)
        print(f"  Found {len(files)} file(s)")

        for file_path in files:
            local_path = bucket_dir / file_path
            if download_file(bucket_name, file_path, local_path):
                downloaded_files += 1
                print(f"  Downloaded: {file_path}")

    print(f"\nStorage backup complete: {downloaded_files}/{total_files} files downloaded")

if __name__ == '__main__':
    backup_storage()
