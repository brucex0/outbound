#!/usr/bin/env python3
"""Check newly added UI color definitions; see docs/design-system.md."""
import argparse
import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
PALETTES = {
    'ios/Outbound/Outbound/DesignSystem/OutboundDesignSystem.swift',
    'android/core/designsystem/src/main/kotlin/com/plainstride/outbound/core/designsystem/PlainstrideTheme.kt',
}
RULES = {
    '.swift': re.compile(r'\b(?:Color|UIColor)\s*\(\s*(?:red|white|hue|hex|rgb|colorLiteralRed)\s*:'),
    '.kt': re.compile(r'\bColor\s*\(\s*(?:0[xX][0-9a-fA-F]|\d|(?:red|green|blue)\s*=)|\b(?:lightColorScheme|darkColorScheme)\s*\('),
}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--base', required=True, help='Commit before the changes (working tree included)')
    args = parser.parse_args()
    try:
        diff = subprocess.check_output(
            ['git', 'diff', '--no-ext-diff', '--no-renames', '--unified=0', args.base, '--', 'ios/', 'android/'],
            cwd=ROOT, text=True,
        )
    except subprocess.CalledProcessError:
        return 2
    path = None
    number = 0
    failures = []
    for line in diff.splitlines():
        if line.startswith('+++ b/'):
            path = line[6:]
        elif line.startswith('@@'):
            number = int(re.search(r'\+(\d+)', line).group(1)) - 1
        elif line.startswith('+') and path:
            number += 1
            rule = RULES.get(Path(path).suffix)
            if not rule or path in PALETTES:
                continue
            source = line[1:]
            if source.lstrip().startswith(('//', '*', '/*')) or not rule.search(source):
                continue
            lines = (ROOT / path).read_text().splitlines()
            context = '\n'.join(lines[max(0, number - 2):number])
            allowance = re.search(r'//\s*design-system-allow:\s*([^\n]+)', context)
            if allowance and len(allowance.group(1).strip()) >= 10:
                continue
            failures.append(f'{path}:{number}: use shared theme colors; intentional exceptions need a specific design-system-allow reason')
        elif line.startswith(' '):
            number += 1
    if failures:
        print('\n'.join(failures), file=sys.stderr)
        return 1
    print('Design system check passed (added lines only).')
    return 0


if __name__ == '__main__':
    sys.exit(main())
