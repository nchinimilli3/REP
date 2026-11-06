#!/usr/bin/env python3
"""Configure a friend's checkout without accessing installed apps or runtime data."""
import argparse
import plistlib
import re
from pathlib import Path


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--team', required=True, help='Your 10-character Apple Team ID')
    parser.add_argument('--bundle-id', required=True, help='Unique iPhone identifier, e.g. com.yourname.rep')
    parser.add_argument('--dry-run', action='store_true')
    args = parser.parse_args()
    if not re.fullmatch(r'[A-Z0-9]{10}', args.team):
        parser.error('Team ID must contain 10 uppercase letters or digits.')
    if not re.fullmatch(r'[A-Za-z0-9-]+(?:\.[A-Za-z0-9-]+)+', args.bundle_id):
        parser.error('Use a reverse-domain bundle identifier containing letters, digits, dots or hyphens.')
    root = Path(__file__).resolve().parent.parent
    project = root / 'fitness/fitness.xcodeproj/project.pbxproj'
    info = root / 'fitness/WatchInfo.plist'
    original = project.read_text()
    watch_info = plistlib.loads(info.read_bytes())
    old_id = watch_info['WKCompanionAppBundleIdentifier']
    if not re.fullmatch(r'[A-Za-z0-9-]+(?:\.[A-Za-z0-9-]+)+', old_id):
        parser.error('Unexpected existing companion identifier; configure signing manually in Xcode.')
    if not re.search(r'PRODUCT_BUNDLE_IDENTIFIER = ' + re.escape(old_id) + r';', original):
        parser.error('Project and Watch companion identifiers disagree; resolve them in Xcode first.')
    updated, teams = re.subn(r'DEVELOPMENT_TEAM = [A-Z0-9]+;', f'DEVELOPMENT_TEAM = {args.team};', original)
    if teams != 4:
        parser.error('Unexpected signing configuration; configure signing manually in Xcode.')
    # Replace the companion, both app IDs, and test bundle IDs sharing that prefix.
    updated = updated.replace(old_id, args.bundle_id)
    watch_info['WKCompanionAppBundleIdentifier'] = args.bundle_id
    print(f'iPhone: {args.bundle_id}\nWatch: {args.bundle_id}.watchkitapp\nTeam: {args.team}')
    if args.dry_run:
        print('Dry run: no files changed.')
        return
    project.write_text(updated)
    info.write_bytes(plistlib.dumps(watch_info, sort_keys=False))
    print('Updated project and WatchInfo.plist. Reopen Xcode and verify automatic signing for both apps.')


if __name__ == '__main__':
    main()
