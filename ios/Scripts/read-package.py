#!/usr/bin/env python3
"""Read-only Boji v2 verifier; standard library only, no network or Agent invocation."""
import hashlib
import json
import os
import stat
import sys
from pathlib import Path, PurePosixPath


def verify(root):
    root = Path(root)
    if root.is_symlink() or not root.is_dir():
        raise ValueError('Choose a regular package directory')
    root = root.resolve()
    total = structured = 0
    inventory = set()
    for folder, directories, names in os.walk(root, followlinks=False):
        for name in directories + names:
            path = Path(folder) / name
            if path.is_symlink():
                raise ValueError('Symbolic links are not accepted')
        for name in names:
            path = Path(folder) / name
            if not stat.S_ISREG(path.stat().st_mode):
                raise ValueError('Not a regular file')
            size = path.stat().st_size
            total += size
            if name.endswith('.json'):
                structured += size
            inventory.add(path.relative_to(root).as_posix())
    if total > 2 * 1024**3 or structured > 128 * 1024**2 or len(inventory) > 10011:
        raise ValueError('Resource limit exceeded')
    manifest_path = root / 'manifest.json'
    if manifest_path.stat().st_size > 4 * 1024**2:
        raise ValueError('Manifest too large')
    manifest = json.loads(manifest_path.read_text())
    if manifest['schema_version'] != 2:
        raise ValueError('Unsupported package version')
    entries = manifest['files']
    expected = {item['path'] for item in entries}
    if len(expected) != len(entries) or expected | {'manifest.json'} != inventory:
        raise ValueError('Manifest inventory mismatch')
    for entry in entries:
        rel = PurePosixPath(entry['path'])
        if rel.is_absolute() or '..' in rel.parts or '\\' in entry['path']:
            raise ValueError('Unsafe relative path')
        path = root.joinpath(*rel.parts)
        if not path.resolve().is_relative_to(root):
            raise ValueError('Path escapes package')
        digest = hashlib.sha256()
        size = 0
        with path.open('rb') as source:
            while chunk := source.read(1024 * 1024):
                digest.update(chunk)
                size += len(chunk)
        if size != entry['byte_count'] or digest.hexdigest() != entry['sha256']:
            raise ValueError('Incomplete or modified file: ' + entry['path'])
    records = json.loads((root / 'records.json').read_text())
    estimates = {item['id']: item for item in json.loads((root / 'estimates.json').read_text())}
    photos = {item['id']: item for item in records['photos']}
    meals = [item for item in records['meals'] if not item.get('isDemo') and not item.get('deletedAt')]
    workouts = [item for item in records['workouts'] if not item.get('isDemo') and not item.get('deletedAt')]
    output = {'verified_files': len(entries), 'dataset_id': manifest['dataset_id'], 'revision': manifest['revision'], 'meals': len(meals), 'workouts': len(workouts), 'photos': len(photos)}
    if meals:
        meal = meals[0]
        current = estimates.get(meal.get('currentEstimateID'))
        valid = current and current['inputRevision'] == meal['inputRevision'] and current['source'] != 'demo'
        output['first_meal'] = {'id': meal['id'], 'date': meal['time']['localDay'], 'kcal': current['totalKcal'] if valid else None, 'source': current['source'] if valid else None, 'photo_paths': [photos[p]['relativePath'] for p in meal['photoIDs']], 'history_ids': [item['id'] for item in estimates.values() if item['recordID'] == meal['id']]}
    if workouts:
        workout = workouts[0]
        output['first_workout'] = {'id': workout['id'], 'completed_sets': sum(bool(s['completed']) for e in workout['exercises'] for s in e['sets']), 'energy_history': workout['energyHistory']}
    output['day_summaries'] = records['daySummaries']
    return output


if __name__ == '__main__':
    if len(sys.argv) != 2:
        sys.exit('Usage: python3 read-package.py /path/to/<export-id>.boji')
    try:
        print(json.dumps(verify(sys.argv[1]), ensure_ascii=False, indent=2))
    except (OSError, ValueError, KeyError, TypeError) as error:
        sys.exit('Package verification failed: ' + str(error))
