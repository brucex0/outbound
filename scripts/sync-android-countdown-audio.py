#!/usr/bin/env python3
"""Copy the reviewed countdown subset unchanged, or verify it with --check."""
import argparse
import hashlib
import json
from pathlib import Path
import shutil
import wave


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--check', action='store_true', help='Verify packaged recordings without changing files')
    args = parser.parse_args()
    root = Path(__file__).resolve().parent.parent
    source = root / 'ios/Outbound/Outbound/LiveCoachAudio'
    target = root / 'android/feature/livecoach/src/main/assets/LiveCoachAudio'
    manifest = json.loads((source / 'manifest.json').read_text())
    keys = {f'countdown.{key}' for key in ('five', 'four', 'three', 'two', 'one', 'go')}
    manifest['entries'] = [entry for entry in manifest['entries'] if entry['cueKey'] in keys]
    expected = {(locale, voice, key) for locale in ('en', 'es', 'zh-Hans')
                for voice in ('plainstride_clear_1', 'plainstride_warm_1') for key in keys}
    actual = {(entry['locale'], entry['voiceProfileId'], entry['cueKey']) for entry in manifest['entries']}
    if actual != expected or len(manifest['entries']) != len(expected):
        raise ValueError('Countdown catalog does not cover the complete locale/voice matrix')
    if not args.check:
        target.mkdir(parents=True, exist_ok=True)
    for entry in manifest['entries']:
        name = entry['bundledResourceName'] + '.wav'
        original = source / name
        data = original.read_bytes()
        if len(data) != entry['byteCount'] or hashlib.sha256(data).hexdigest() != entry['sha256']:
            raise ValueError('Reviewed countdown checksum/size mismatch')
        with wave.open(str(original)) as audio:
            if (audio.getnchannels(), audio.getsampwidth(), audio.getframerate()) != (1, 2, 24000):
                raise ValueError('Unexpected countdown PCM format')
        if args.check:
            if (target / name).read_bytes() != data:
                raise ValueError('Android countdown differs from reviewed source')
        else:
            shutil.copyfile(original, target / name)
    if args.check:
        if json.loads((target / 'manifest.json').read_text()) != manifest:
            raise ValueError('Android countdown manifest differs from reviewed subset')
        files = {entry['bundledResourceName'] + '.wav' for entry in manifest['entries']}
        if {path.name for path in target.glob('*.wav')} != files:
            raise ValueError('Android countdown folder contains extra/missing audio')
    else:
        (target / 'manifest.json').write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + '\n')
    print(f'{"Verified" if args.check else "Copied"} {len(expected)} reviewed countdown entries; no audio conversion')


if __name__ == '__main__':
    main()
