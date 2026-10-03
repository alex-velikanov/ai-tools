#!/usr/bin/env bash
# vr.sh --record <base-url>   capture the known-good build as the baseline
# vr.sh --discover <base-url> list linked and sitemap pages that are not in pages.json (changes nothing)
# vr.sh <base-url>            capture the build under test and compare it to the baseline
# The baseline only changes when you --record, so a bad deploy cannot become the new normal.
set -e
cd "$(dirname "$0")"

RECORD=0; DISCOVER=0
if [ "$1" = "--record" ]; then RECORD=1; shift; elif [ "$1" = "--discover" ]; then DISCOVER=1; shift; fi
if [ -z "$1" ]; then
  echo "usage: vr.sh [--record | --discover] <base-url>" >&2
  exit 2
fi
URL=$1

if [ "$DISCOVER" = 1 ]; then
  BASE_URL=$URL exec node discover.mjs
fi

if [ "$RECORD" = 1 ]; then
  trap 'rm -rf baseline.new' EXIT
  rm -rf baseline.new
  OUT=baseline.new BASE_URL=$URL node shoot.mjs
  rm -rf baseline && mv baseline.new baseline
  echo "baseline recorded: $(ls baseline | wc -l | tr -d ' ') screenshots"
  exit 0
fi

if [ -z "$(ls -A baseline 2>/dev/null)" ]; then
  echo "No baseline. Run 'vr.sh --record <base-url>' against the known-good build first." >&2
  exit 2
fi

rm -rf current changed.json blank.json diffs.json report.json warnings.json raw_report.txt raw_report.*.txt judge.tmp
OUT=current BASE_URL=$URL node shoot.mjs
node filter.mjs

if [ "$(tr -d ' \n' < changed.json)" = "[]" ]; then
  echo "[]" > report.json
  echo "[]" > warnings.json
  echo "0 pages compared, nothing changed"
  exit 0
fi

# The judge gets a few screenshot pairs per call (VR_BATCH, default 6): on long lists it has been seen to skim past
# obviously broken pages. Read-only: it may open files but not run anything. VR_MODEL pins the model.
BATCH=${VR_BATCH:-6}
mkdir judge.tmp
node -e "console.log(require('./changed.json').join('\n'))" | split -l "$BATCH" - judge.tmp/files_
: > raw_report.txt
n=0
for f in judge.tmp/files_*; do
  n=$((n+1))
  list=$(paste -sd' ' "$f")
  claude -p "Read rubric.md. For each of these files: $list -- compare \
baseline/<file> against current/<file> and apply the rubric. Print ONLY a \
JSON array as [{file, verdict, severity, findings}] to stdout — no prose, \
no markdown fences. A file present in only one of the two folders means a \
page or section was added or removed: report it." \
    --allowedTools Read ${VR_MODEL:+--model "$VR_MODEL"} > "raw_report.$n.txt"
  { echo "--- batch $n: $list"; cat "raw_report.$n.txt"; } >> raw_report.txt
done
rm -rf judge.tmp

# Model output isn't always fence-free despite instructions: find the JSON array defensively instead of trusting
# exact compliance. Prose may contain brackets ("[2 pages]"), so try each "[" until one decodes to a list of objects.
# On top of the judge: a page that went blank always fails, and a page the judge passed (or never mentioned) while
# VR_WARN_DIFF_PCT or more of its pixels differ gets a warning. Warnings never change the exit code.
python3 - "${VR_WARN_DIFF_PCT:-50}" <<'PYEOF'
import glob, json, re, sys

warn_pct = float(sys.argv[1])
dec = json.JSONDecoder()

def parse(text):
    found = None
    for m in re.finditer(r'\[', text):
        try:
            obj, _ = dec.raw_decode(text, m.start())
        except ValueError:
            continue
        if isinstance(obj, list) and all(isinstance(r, dict) for r in obj):
            if obj or found is None:
                found = obj
            if obj:
                break
    return found

report = []
for path in sorted(glob.glob('raw_report.*.txt'), key=lambda p: int(re.search(r'\.(\d+)\.txt$', p).group(1))):
    text = open(path).read()
    part = parse(text)
    if part is None:
        print(f'No JSON array found in model output ({path}):', file=sys.stderr)
        print(text, file=sys.stderr)
        sys.exit(1)
    report += part

changed = json.load(open('changed.json'))
diffs = json.load(open('diffs.json'))
by_file = {}
for r in report:
    by_file.setdefault(r.get('file'), r)
report = list(by_file.values())

for f in json.load(open('blank.json')):
    note = {'what': 'The page is blank (one flat colour) where the baseline was not.', 'where': 'entire page', 'confidence': 'high'}
    r = by_file.get(f)
    if r is None:
        r = {'file': f, 'verdict': 'fail', 'severity': 5, 'findings': [], 'judge_severity': None}
        report.append(r)
        by_file[f] = r
    elif r.get('severity', 0) < 5:
        r['judge_severity'] = r.get('severity', 0)
        r['verdict'], r['severity'] = 'fail', 5
    else:
        continue
    r['findings'] = (r['findings'] if isinstance(r.get('findings'), list) else []) + [note]

warnings = []
for f in changed:
    r = by_file.get(f)
    sev = (r or {}).get('judge_severity', (r or {}).get('severity', 0)) or 0
    if r is None:
        warnings.append({'file': f, 'warning': 'The judge returned no verdict for this file.'})
    if sev < 3 and diffs.get(f, 0) >= warn_pct and not (r and r.get('severity', 0) >= 3):
        warnings.append({'file': f, 'warning': f"{diffs[f]}% of pixels differ but the judge gave severity {sev}. Look at it yourself."})

json.dump(report, open('report.json', 'w'), indent=2)
json.dump(warnings, open('warnings.json', 'w'), indent=2)

worst = max((r.get('severity', 0) for r in report), default=0)
print(f'{len(report)} pages compared, worst severity {worst}')
for w in warnings:
    print(f"WARNING {w['file']}: {w['warning']}")
sys.exit(1 if worst >= 3 else 0)
PYEOF
