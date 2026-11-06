#!/usr/bin/env python3
"""Package the existing REP artwork in explicit watchOS icon slots using macOS sips."""
import json
from pathlib import Path
import subprocess

root = Path(__file__).resolve().parent.parent
catalog = root / 'fitness/fitness Watch App/Assets.xcassets/AppIcon.appiconset'
source = catalog / 'REP-AppIcon.png'
slots = []

def add(size, role, subtype=None, scale=2):
    pixels = round(size * scale)
    item = dict(idiom='watch', size=f'{size:g}x{size:g}', scale=f'{scale}x',
                role=role, filename=f'REP-AppIcon-{pixels}.png')
    if subtype:
        item['subtype'] = subtype
    slots.append(item)

for size, subtype in [(24, '38mm'), (27.5, '42mm'), (33, '45mm')]:
    add(size, 'notificationCenter', subtype)
for scale in (2, 3):
    add(29, 'companionSettings', scale=scale)
for size, subtype in [(40, '38mm'), (44, '40mm'),
                       (46, '41mm'), (50, '44mm'), (51, '45mm'), (54, '49mm')]:
    add(size, 'appLauncher', subtype)
for size, subtype in [(86, '38mm'), (98, '42mm'), (108, '44mm'),
                       (117, '45mm'), (129, '49mm')]:
    add(size, 'quickLook', subtype)
for filename in sorted({item['filename'] for item in slots}):
    pixels = int(filename.removesuffix('.png').rsplit('-', 1)[1])
    subprocess.run(['/usr/bin/sips', '-z', str(pixels), str(pixels), str(source),
                    '--out', str(catalog / filename)], check=True, capture_output=True)
slots.append(dict(idiom='watch-marketing', size='1024x1024', scale='1x', filename=source.name))
(catalog / 'Contents.json').write_text(json.dumps(dict(images=slots, info=dict(author='xcode', version=1)), indent=2) + '\n')
print(f'Generated {len(slots)} explicit slots from the unchanged master.')
