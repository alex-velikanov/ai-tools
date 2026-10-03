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

rm -rf current changed.json report.json raw_report.txt
OUT=current BASE_URL=$URL node shoot.mjs
node filter.mjs

if [ "$(tr -d ' \n' < changed.json)" = "[]" ]; then
  echo "[]" > report.json
  echo "0 pages compared, nothing changed"
  exit 0
fi

# Read-only: the judge may open files but not run anything. VR_MODEL pins the model so results are comparable between runs.
claude -p "Read rubric.md. For each filename in changed.json, compare \
baseline/<file> against current/<file> and apply the rubric. Print ONLY a \
JSON array as [{file, verdict, severity, findings}] to stdout — no prose, \
no markdown fences. A file present in only one of the two folders means a \
page or section was added or removed: report it." \
  --allowedTools Read ${VR_MODEL:+--model "$VR_MODEL"} > raw_report.txt

# Model output isn't always fence-free despite instructions — find the JSON array defensively instead of
# trusting exact compliance. Prose may contain brackets ("[2 pages]"), so try each "[" until one decodes
# to a list of objects.
python3 -c "
import json, re, sys

text = open('raw_report.txt').read()
dec = json.JSONDecoder()
report = None
for m in re.finditer(r'\\[', text):
    try:
        obj, _ = dec.raw_decode(text, m.start())
    except ValueError:
        continue
    if isinstance(obj, list) and all(isinstance(r, dict) for r in obj):
        if obj or report is None:
            report = obj
        if obj:
            break
if report is None:
    print('No JSON array found in model output:', file=sys.stderr)
    print(text, file=sys.stderr)
    sys.exit(1)

json.dump(report, open('report.json', 'w'), indent=2)

worst = max((r.get('severity', 0) for r in report), default=0)
print(f'{len(report)} pages compared, worst severity {worst}')
sys.exit(1 if worst >= 3 else 0)
"
