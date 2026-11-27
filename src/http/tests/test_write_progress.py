#!/usr/bin/env python3
"""Exercise the HTTP and core writers with controlled send results.

The extracted production functions are compiled unchanged in a temporary build
with no server or network dependencies. Run with make -C src/http/tests.
"""
import os
from pathlib import Path
import re
import shlex
import subprocess
import tempfile
import unittest

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]


def extract_sources():
    parts = []
    for filename, name in [
        ('src/http/ngx_http_write_filter_module.c', 'ngx_http_write_filter'),
        ('src/core/ngx_output_chain.c', 'ngx_chain_writer'),
    ]:
        source = (ROOT / filename).read_text()
        matches = list(re.finditer(
            r'^ngx_int_t\n' + name + r'\([^;{]*\{[\s\S]*?^\}', source, re.M))
        if len(matches) != 1:
            raise AssertionError('cannot uniquely extract production function: ' + name)
        match = matches[0]
        parts.append('#line %d "%s"\n%s\n' % (
            source[:match.start()].count('\n') + 1, ROOT / filename, match.group()))
    return '\n'.join(parts)


def run_c(functions, private=0):
    with tempfile.TemporaryDirectory(prefix='write-progress-unit-') as tmp:
        build = Path(tmp)
        (build / 'write_progress_functions.inc').write_text(functions)
        command = shlex.split(os.environ.get('CC', 'cc')) + [
            '-std=c99', '-Wall', '-Wextra', '-Werror', '-g', '-O0',
            '-DT_NGX_REQ_STATUS=%d' % private,
            '-DT_NGX_HTTP_STAT_TIME=%d' % private,
        ] + shlex.split(os.environ.get('CFLAGS', '')) + [
            '-I' + tmp, str(HERE / 'test_write_progress.c'),
            '-o', str(build / 'unit'),
        ]
        compiled = subprocess.run(command, stdout=subprocess.PIPE,
                                  stderr=subprocess.STDOUT, text=True, timeout=60)
        if compiled.returncode:
            raise AssertionError('unit compilation failed:\n' + compiled.stdout)
        return subprocess.run([str(build / 'unit')], stdout=subprocess.PIPE,
                              stderr=subprocess.STDOUT, text=True, timeout=10)


class TestWriteProgress(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.functions = extract_sources()

    def test_production_writers(self):
        """No progress, partial/full sends, retries, errors, buffering and rate limits."""
        for private in (0, 1):
            with self.subTest(private=private):
                result = run_c(self.functions, private)
                self.assertEqual(result.returncode, 0, result.stdout)
                print(result.stdout.strip())


if __name__ == '__main__':
    unittest.main()
