#!/usr/bin/python3
"""Privileged, deliberately restricted system locale operation for Pond."""
import os
from pathlib import Path
import re
import subprocess
import sys
import tempfile

LOCALES = {'en': 'en_US.UTF-8', 'fr': 'fr_FR.UTF-8'}
LOCALE_GEN = Path('/etc/locale.gen')
SUPPORTED = Path('/usr/share/i18n/SUPPORTED')
CATEGORIES = ('LC_ADDRESS', 'LC_COLLATE', 'LC_CTYPE', 'LC_IDENTIFICATION',
              'LC_MEASUREMENT', 'LC_MESSAGES', 'LC_MONETARY', 'LC_NAME',
              'LC_NUMERIC', 'LC_PAPER', 'LC_TELEPHONE', 'LC_TIME')


def normalize(value):
    return value.lower().replace('-', '').replace('_', '').replace('.', '')


def installed(locale):
    output = subprocess.check_output(['/usr/bin/locale', '-a'], text=True)
    return normalize(locale) in {normalize(value) for value in output.splitlines()}


def enable_generation(locale):
    """Persist an explicitly allowed locale in locale.gen, preserving other entries."""
    if not LOCALE_GEN.is_file() or LOCALE_GEN.is_symlink():
        raise RuntimeError('The system locale generation configuration is unavailable')
    if f'{locale} UTF-8' not in SUPPORTED.read_text().splitlines():
        raise RuntimeError('The requested locale is not supported by this system')
    original = LOCALE_GEN.read_text()
    pattern = re.compile(r'^[ \t]*#?[ \t]*' + re.escape(locale) + r'[ \t]+UTF-8[ \t]*(?:#.*)?$', re.I | re.M)
    if pattern.search(original):
        updated = pattern.sub(f'{locale} UTF-8', original, count=1)
    else:
        updated = original.rstrip('\n') + '\n' + f'{locale} UTF-8\n'
    if updated == original:
        return
    metadata = LOCALE_GEN.stat()
    fd, filename = tempfile.mkstemp(prefix='.locale.gen.', dir=str(LOCALE_GEN.parent))
    try:
        os.fchmod(fd, metadata.st_mode & 0o7777)
        os.fchown(fd, metadata.st_uid, metadata.st_gid)
        with os.fdopen(fd, 'w') as output:
            output.write(updated)
        os.replace(filename, LOCALE_GEN)
    finally:
        if os.path.exists(filename):
            os.unlink(filename)


def main(args):
    if len(args) != 2 or args[0] not in LOCALES or args[1] not in ('existing', 'generate'):
        raise ValueError('Invalid locale request')
    locale = LOCALES[args[0]]
    if not installed(locale):
        if args[1] != 'generate':
            raise RuntimeError('The locale is not installed')
        subprocess.run(['/usr/bin/localedef', '-i', locale.split('.')[0], '-f', 'UTF-8', locale], check=True)
        if not installed(locale):
            raise RuntimeError('Locale generation failed')
    if args[1] == 'generate':
        enable_generation(locale)
    # Set every category explicitly: localectl rejects empty locale assignments.
    subprocess.run(['/usr/bin/localectl', 'set-locale', 'LANG=' + locale,
                    *(category + '=' + locale for category in CATEGORIES)], check=True)


if __name__ == '__main__':
    try:
        main(sys.argv[1:])
    except (OSError, ValueError, RuntimeError, subprocess.SubprocessError) as error:
        print(str(error), file=sys.stderr)
        sys.exit(1)
