#!/bin/zsh
set -euo pipefail
cd "${0:A:h}"
mkdir -p evidence
./build.sh
zsh -n scripts/install-override.command
python3 scripts/generate_override.py --compare Resources/DisplayProductID-2750 > evidence/override-check.txt
python3 - <<'PY_SNAPSHOT'
from pathlib import Path
p = Path('/Library/Displays/Contents/Resources/Overrides/DisplayVendorID-4c23/DisplayProductID-2750')
if not p.is_file():
    raise SystemExit('Full verification requires the OF27QT mode override to be installed and activated first.')
Path('evidence/verification-override-before.plist').write_bytes(p.read_bytes())
PY_SNAPSHOT
swift inspect.swift > evidence/verification-start.json
./build/MiniDisplay.app/Contents/MacOS/MiniDisplay --self-test > evidence/self-test.txt
MINIDISPLAY_PREVIEW="$PWD/evidence/app-window.png" ./build/MiniDisplay.app/Contents/MacOS/MiniDisplay --smoke-test > evidence/smoke-test.txt 2>&1
swift inspect.swift > evidence/verification-end.json
python3 - <<'PY'
import json
from pathlib import Path
before = json.loads(Path('evidence/verification-start.json').read_text())
after = json.loads(Path('evidence/verification-end.json').read_text())
assert before == after, 'Display state or mode list changed during verification'
p = Path('/Library/Displays/Contents/Resources/Overrides/DisplayVendorID-4c23/DisplayProductID-2750')
assert p.read_bytes() == Path('evidence/verification-override-before.plist').read_bytes(), 'Installed override differs from original evidence'
print('PASS: identical before/after topology and modes; installed override unchanged')
PY
codesign --verify --strict build/MiniDisplay.app
cat evidence/self-test.txt evidence/smoke-test.txt evidence/override-check.txt
