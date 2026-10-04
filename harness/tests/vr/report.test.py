"""Exercise report.py with judge severities that are not JSON integers."""
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

REPORT = Path(sys.argv.pop(1)).resolve() / 'report.py'


class SeverityTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)

    def write(self, name, value):
        (self.root / name).write_text(json.dumps(value))

    def read(self, name):
        return json.loads((self.root / name).read_text())

    def run_report(self, mode, expected=0):
        result = subprocess.run([sys.executable, str(REPORT), mode], cwd=self.root, capture_output=True, text=True)
        self.assertEqual(result.returncode, expected, result.stdout + result.stderr)

    def test_merge_normalizes_before_blank_and_suspect_checks(self):
        records = [{'file': str(i), 'severity': value, 'seen': 'page'}
                   for i, value in enumerate(['4', None, 'bad', {}, [], 2.9, float('inf')])]
        records.append({'file': 'missing', 'seen': 'page'})
        self.write('raw_report.1.txt', records)
        self.write('changed.json', [r['file'] for r in records])
        self.write('diffs.json', {r['file']: 60 for r in records})
        self.run_report('merge')
        self.assertEqual([r['severity'] for r in self.read('first.json')], [4, 0, 0, 0, 0, 2, 0, 0])
        self.assertEqual(len(self.read('suspects.json')), 7)
        self.run_report('final', 1)
        self.write('blank.json', ['0', '1'])
        self.run_report('merge')
        self.assertEqual([r['severity'] for r in self.read('first.json')][:2], [5, 5])
        self.assertEqual([r['judge_severity'] for r in self.read('first.json')[:2]], [4, 0])

    def test_recheck_normalizes_and_never_lowers(self):
        for value, expected in [('4', 4), ('1', 2), (None, 2), ('bad', 2), ({}, 2), ([], 2), (float('inf'), 2)]:
            with self.subTest(value=value):
                self.write('raw_report.1.txt', [{'file': 'page', 'severity': '2'}])
                self.write('changed.json', ['page'])
                self.run_report('merge')
                self.write('recheck.1.txt', [{'file': 'page', 'severity': value}])
                self.run_report('final', int(expected >= 3))
                record = self.read('report.json')[0]
                self.assertEqual(record['severity'], expected)
                self.assertEqual(record['first_severity'], 2)

    def test_missing_first_verdict_uses_normalized_recheck(self):
        self.write('raw_report.1.txt', [])
        self.write('changed.json', ['page'])
        self.run_report('merge')
        self.write('recheck.1.txt', [{'file': 'page', 'severity': '3'}])
        self.run_report('final', 1)
        self.assertEqual(self.read('report.json')[0]['severity'], 3)


if __name__ == '__main__':
    unittest.main()
