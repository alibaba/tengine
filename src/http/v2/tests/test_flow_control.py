#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""C unit test driver and patch-omission negative controls for CVE-2026-123007.

Only complete production functions are extracted into temporary build
artifacts; production sources are never modified and no configure is needed.
CC/CFLAGS override the compiler and flags, e.g. CFLAGS='-fsanitize=address,undefined'.
Run: python3 -m unittest discover -v -s src/http/v2/tests
With an existing make build, set H2_INTEGRATION_NEGATIVE=1 to additionally
verify that the integration test detects the old window check.
"""
import os
from pathlib import Path
import re
import shlex
import subprocess
import tempfile
import unittest

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[3]
V2 = ROOT / 'src/http/v2'
FUNCTIONS = {
    'ngx_http_v2.c': ['ngx_http_v2_state_window_update'],
    'ngx_http_v2_filter_module.c': [
        'ngx_http_v2_send_chain', 'ngx_http_v2_data_frame_handler',
        'ngx_http_v2_filter_cleanup'],
}
CONSTANTS = [
    'NGX_HTTP_V2_MAX_WINDOW', 'NGX_HTTP_V2_DEFAULT_WINDOW',
    'NGX_HTTP_V2_FRAME_HEADER_SIZE', 'NGX_HTTP_V2_WINDOW_UPDATE_SIZE',
    'NGX_HTTP_V2_FLOW_CTRL_ERROR', 'NGX_HTTP_V2_PROTOCOL_ERROR',
    'NGX_HTTP_V2_SIZE_ERROR', 'NGX_HTTP_V2_INTERNAL_ERROR',
]


def extract_sources():
    parts = []
    for filename, names in FUNCTIONS.items():
        source = (V2 / filename).read_text()
        for name in names:
            # Project-style function definitions start with 'static' at the
            # beginning of a line and end with '}' at the beginning of a line.
            matches = list(re.finditer(
                r'^static[^\n]*\n' + name + r'\([^;{]*\{[\s\S]*?^\}',
                source, re.M))
            if len(matches) != 1:
                raise AssertionError('cannot uniquely extract production function: ' + name)
            match = matches[0]
            line = source[:match.start()].count('\n') + 1
            parts.append('#line %d "%s"\n%s\n' % (
                line, V2 / filename, match.group()))
    source = (V2 / 'ngx_http_v2.h').read_text() + (V2 / 'ngx_http_v2.c').read_text()
    definitions = []
    for name in CONSTANTS:
        matches = re.findall(r'^#define\s+' + name + r'\s+[^\n]+', source, re.M)
        if len(matches) != 1:
            raise AssertionError('cannot uniquely extract production constant: ' + name)
        definitions.extend(matches)
    return '\n'.join(parts), '\n'.join(definitions) + '\n'


def run_c(functions, constants):
    # All files below are test build artifacts; production code is read-only.
    with tempfile.TemporaryDirectory(prefix='h2-flow-unit-') as tmp:
        build = Path(tmp)
        (build / 'flow_control_functions.inc').write_text(functions)
        (build / 'flow_control_constants.inc').write_text(constants)
        command = shlex.split(os.environ.get('CC', 'cc')) + [
            '-std=c99', '-Wall', '-Wextra', '-Werror', '-g', '-O0',
        ] + shlex.split(os.environ.get('CFLAGS', '')) + [
            '-I' + tmp, '-I' + str(ROOT / 'src/core'),
            str(HERE / 'test_flow_control.c'), '-o', str(build / 'unit'),
        ]
        compiled = subprocess.run(command, stdout=subprocess.PIPE,
                                  stderr=subprocess.STDOUT, text=True, timeout=60)
        if compiled.returncode:
            raise AssertionError('C unit test compilation failed:\n' + compiled.stdout)
        return subprocess.run([str(build / 'unit')], stdout=subprocess.PIPE,
                              stderr=subprocess.STDOUT, text=True, timeout=10)


class TestHttp2FlowControl(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.functions, cls.constants = extract_sources()

    def test_production_functions(self):
        """Boundaries, queueing, partial/full send, cancel, non-DATA, waiting queue."""
        result = run_c(self.functions, self.constants)
        self.assertEqual(result.returncode, 0, result.stdout)
        print(result.stdout.strip())

    @unittest.skipUnless(os.environ.get('H2_INTEGRATION_NEGATIVE') == '1',
                         'set H2_INTEGRATION_NEGATIVE=1 to run the binary negative control')
    def test_integration_negative_control(self):
        """Patch only the window check in a temporary object; workspace sources and objs/nginx stay untouched."""
        source_path = 'src/http/v2/ngx_http_v2.c'
        dry = subprocess.run(
            ['make', '-n', '-f', 'objs/Makefile', '-W', source_path],
            cwd=ROOT, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
            text=True, timeout=30)
        self.assertEqual(dry.returncode, 0, dry.stdout)
        recipes = [shlex.split(line) for line in
                   dry.stdout.replace('\\\n', ' ').splitlines() if line.strip()]
        compiles = [args for args in recipes if '-c' in args and source_path in args]
        links = [args for args in recipes if '-o' in args and 'objs/nginx' in args]
        self.assertEqual(len(compiles), 1, 'cannot uniquely locate the compile command')
        self.assertEqual(len(links), 1, 'cannot uniquely locate the link command')
        source = (ROOT / source_path).read_text()
        old = 'NGX_HTTP_V2_MAX_WINDOW - h2c->send_window - h2c->send_queued'
        self.assertEqual(source.count(old), 1)
        mutated = source.replace(old, 'NGX_HTTP_V2_MAX_WINDOW - h2c->send_window')
        with tempfile.TemporaryDirectory(prefix='h2-flow-integration-') as tmp:
            obj, binary = str(Path(tmp) / 'v2.o'), str(Path(tmp) / 'nginx')
            compile_command = compiles[0][:]
            original_obj = compile_command[compile_command.index('-o') + 1]
            compile_command[compile_command.index('-o') + 1] = obj
            at = compile_command.index(source_path)
            compile_command[at:at + 1] = ['-x', 'c', '-']
            built = subprocess.run(compile_command, input=mutated, cwd=ROOT,
                                   stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                                   text=True, timeout=60)
            self.assertEqual(built.returncode, 0, built.stdout)
            link_command = [obj if arg == original_obj else arg for arg in links[0]]
            link_command[link_command.index('-o') + 1] = binary
            linked = subprocess.run(link_command, cwd=ROOT, stdout=subprocess.PIPE,
                                    stderr=subprocess.STDOUT, text=True, timeout=60)
            self.assertEqual(linked.returncode, 0, linked.stdout)
            for target, patched in [(ROOT / 'objs/nginx', True), (binary, False)]:
                env = dict(os.environ, TEST_NGINX_BINARY=str(target))
                env.pop('TEST_NGINX_VERBOSE', None)
                env.pop('TEST_NGINX_LEAVE', None)
                result = subprocess.run(
                    ['prove', '-v', '-I', 'tests/nginx-tests/nginx-tests/lib',
                     'tests/nginx-tests/tengine-tests/h2_flow_control.t'],
                    cwd=ROOT, env=env, stdout=subprocess.PIPE,
                    stderr=subprocess.STDOUT, text=True, timeout=60)
                if patched:
                    self.assertEqual(result.returncode, 0, result.stdout)
                else:
                    self.assertNotEqual(result.returncode, 0, result.stdout)
                    self.assertIn('not ok 6 -', result.stdout)
                    self.assertIn('not ok 7 -', result.stdout)
                    self.assertIn('ok 14 -', result.stdout)
            print('integration negative control: fixed binary passes, binary without the window check is detected')

    def test_patch_omission_controls(self):
        """Revert each fix in turn; assertions must catch it so the tests do not merely validate a copied algorithm."""
        omissions = [
            ('WINDOW_UPDATE ignores queued bytes',
             'NGX_HTTP_V2_MAX_WINDOW - h2c->send_window - h2c->send_queued',
             'NGX_HTTP_V2_MAX_WINDOW - h2c->send_window'),
            ('DATA enqueue not accounted', 'h2c->send_queued += frame_size;', ''),
            ('DATA completion not released', 'h2c->send_queued -= frame->length;', ''),
            ('cancel not released', 'h2c->send_queued -= window;', ''),
            ('cancel wrongly refunds non-DATA frames',
             'if (frame->handler == ngx_http_v2_data_frame_handler) {\n'
             '                window += frame->length;\n            }',
             'window += frame->length;'),
        ]
        for label, old, new in omissions:
            with self.subTest(omission=label):
                self.assertEqual(self.functions.count(old), 1,
                                 'negative control anchor lost: ' + label)
                result = run_c(self.functions.replace(old, new), self.constants)
                self.assertNotEqual(result.returncode, 0,
                                    'patch omission not detected: ' + label + '\n' + result.stdout)
                self.assertIn('assertion failed', result.stdout)


if __name__ == '__main__':
    unittest.main()
