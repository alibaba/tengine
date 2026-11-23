#!/usr/bin/env python3
"""Compile the complete production SSL error function and test its log policy.

No configure or running nginx is needed. Production sources are read-only;
only temporary test build artifacts contain extracted code and mutations.
OpenSSL compile/link flags come from pkg-config or CPPFLAGS/LDLIBS.
SSL_BASELINE_BINARY optionally tests an unfixed binary against HTTP/2 resets.
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
SOURCE = ROOT / 'src/event/ngx_event_openssl.c'


def extract_sources():
    source = SOURCE.read_text()
    matches = list(re.finditer(
        r'^void\nngx_ssl_connection_error\([^;{]*\{[\s\S]*?^\}', source, re.M))
    if len(matches) != 1:
        raise AssertionError('cannot uniquely extract ngx_ssl_connection_error')
    function = matches[0].group()
    connection = (ROOT / 'src/core/ngx_connection.h').read_text()
    enums = re.findall(
        r'^typedef enum \{\n\s*NGX_ERROR_ALERT[\s\S]*?^\} ngx_connection_log_error_e;',
        connection, re.M)
    if len(enums) != 1:
        raise AssertionError('cannot uniquely extract connection log policies')
    logs = (ROOT / 'src/core/ngx_log.h').read_text()
    constants = re.findall(r'^#define NGX_LOG_\w+\s+[^\n]+', logs, re.M)
    return function, '\n'.join(enums + constants) + '\n'


def openssl_flags():
    if 'LDLIBS' in os.environ:
        return (shlex.split(os.environ.get('CPPFLAGS', '')),
                shlex.split(os.environ['LDLIBS']))
    try:
        cflags = subprocess.check_output(
            ['pkg-config', '--cflags', 'openssl'], text=True).strip()
        libs = subprocess.check_output(
            ['pkg-config', '--libs', 'openssl'], text=True).strip()
        return shlex.split(cflags), shlex.split(libs)
    except (OSError, subprocess.CalledProcessError):
        return shlex.split(os.environ.get('CPPFLAGS', '')), ['-lssl', '-lcrypto']


def run_c(function, constants, ali=1, win32=0):
    with tempfile.TemporaryDirectory(prefix='ssl-log-unit-') as tmp:
        build = Path(tmp)
        (build / 'ssl_error_functions.inc').write_text(function)
        (build / 'ssl_error_constants.inc').write_text(constants)
        cflags, libs = openssl_flags()
        command = shlex.split(os.environ.get('CC', 'cc')) + [
            '-std=c99', '-Wall', '-Wextra', '-Werror', '-g', '-O0',
            '-DT_NGX_SSL_ERR_LOG_ALI=%d' % ali, '-DNGX_WIN32=%d' % win32,
            '-I' + tmp,
        ] + shlex.split(os.environ.get('CFLAGS', '')) + cflags + [
            str(HERE / 'test_ssl_error_log_level.c'), '-o', str(build / 'unit'),
        ] + libs
        result = subprocess.run(command, stdout=subprocess.PIPE,
                                stderr=subprocess.STDOUT, text=True, timeout=60)
        if result.returncode:
            raise AssertionError('unit compilation failed:\n' + result.stdout)
        return subprocess.run([str(build / 'unit')], stdout=subprocess.PIPE,
                              stderr=subprocess.STDOUT, text=True, timeout=30)


class TestSslErrorLogLevel(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.function, cls.constants = extract_sources()

    def test_production_policy_matrix(self):
        """Phases, policies, syscalls, TLS errors, SNI, and disabled macro."""
        for ali, win32 in [(1, 0), (0, 0), (1, 1)]:
            with self.subTest(ali=ali, win32=win32):
                result = run_c(self.function, self.constants, ali, win32)
                self.assertEqual(result.returncode, 0, result.stdout)
                print(result.stdout.strip())

    @unittest.skipUnless(os.environ.get('SSL_BASELINE_BINARY'),
                         'set SSL_BASELINE_BINARY to run the HTTP/2 negative control')
    def test_http2_baseline_negative_control(self):
        """An unfixed binary must emit error-level resets, not just reject a new directive."""
        integration = ROOT / 'tests/nginx-tests/tengine-tests/h2_ssl_error_log_level.t'
        source = integration.read_text()
        directive = 'ssl_handshake_error_log_level error;'
        self.assertEqual(source.count(directive), 1)
        with tempfile.TemporaryDirectory(prefix='ssl-log-baseline-') as tmp:
            # The baseline lacks the new directive, so remove only that fixture
            # setting. Assertions and the actual HTTP/2 traffic remain intact.
            test = Path(tmp) / integration.name
            test.write_text(source.replace(directive, ''))
            env = dict(os.environ, TEST_NGINX_BINARY=os.environ['SSL_BASELINE_BINARY'])
            result = subprocess.run(
                ['prove', '-v', '-I' + str(ROOT / 'tests/nginx-tests/nginx-tests/lib'),
                 str(test)], cwd=ROOT, env=env, stdout=subprocess.PIPE,
                stderr=subprocess.STDOUT, text=True, timeout=90)
            self.assertNotEqual(result.returncode, 0, result.stdout)
            for assertion in [2, 4, 5, 6]:
                self.assertIn('not ok %d -' % assertion, result.stdout)
            self.assertRegex(result.stdout, r'\[error\].*SSL_read\(\) failed.*reset by peer')
            print('HTTP/2 baseline negative control: error-level resets detected')

    def test_patch_omission_controls(self):
        """Tests must detect the old behavior and loss of either phase guard."""
        mutations = [
            ('old unconditional promotion', 'level = NGX_LOG_INFO;',
             'level = NGX_LOG_ERR;', 2),
            ('promotion after handshake', '&& !c->ssl->handshaked', '', 1),
            ('downgrades critical failures', 'level == NGX_LOG_INFO\n        && ',
             '', 1),
        ]
        for label, old, new, count in mutations:
            with self.subTest(mutation=label):
                self.assertEqual(self.function.count(old), count)
                result = run_c(self.function.replace(old, new), self.constants)
                self.assertNotEqual(result.returncode, 0, result.stdout)
                self.assertIn('assertion failed', result.stdout)


if __name__ == '__main__':
    unittest.main()
