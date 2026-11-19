#!/usr/bin/env python
# encoding: utf-8

import unittest
import os
import time
import sys
import subprocess
import re

sys.path.append("../../../tests/unittest_pycommon")
import config
import nginx

class TestMaxStreams(unittest.TestCase):
    """Tests for the xquic_max_streams_bidi and xquic_max_streams_uni directives"""

    p = nginx.Nginx(config.TENGINE)

    @classmethod
    def setUpClass(self):
        """Setup before tests: copy test_client and set permissions"""
        os.system("cp -f ../../../libs/xquic/build/tests/test_client ./test_client")
        os.system("chmod +x test_client")
        print("Test client prepared")

    @classmethod
    def tearDownClass(self):
        """Cleanup after tests: stop nginx"""
        try:
            self.p.stop()
        except:
            pass
        print("Test completed")

    def stop_nginx(self):
        """Stop nginx and wait"""
        self.p.stop()
        time.sleep(2)

    def test_1_max_streams_custom_values(self):
        print("\n=== Test case 1: custom max_streams configuration ===")

        # ========== Phase 1: test -P 20 (normal case) ==========
        print("\n--- Phase 1: test -P 20 (should succeed) ---")

        # clear logs
        os.system("echo '' > logs/error.log")
        os.system("echo '' > logs/xquic.log")
        os.system("echo '' > clog")

        # start nginx with custom max_streams configuration
        self.stop_nginx()
        self.p.start("conf/nginx_max_streams.conf")
        time.sleep(2)

        # run test_client connection test, P=20 means create 20 concurrent streams
        cmd = "./test_client -a 127.0.0.1 -p 2081 -u 'https://test.taobao.com/test' -D 1 -b 1 -B 1 -s 10 -P 20 -1 -t 10 2>&1"
        try:
            result = subprocess.run(cmd, shell=True, timeout=15,
                                   stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                                   universal_newlines=True)
            print(f"Client output (P=20): {result.stdout[:200]}")
        except subprocess.TimeoutExpired:
            print("Client test timeout (expected)")
        except Exception as e:
            print(f"Client test exception: {e}")

        time.sleep(3)

        # read xqc_conn_destroy report records from xquic.log
        f = os.popen("cat logs/xquic.log | grep 'xqc_conn_destroy' | grep 'report'")
        xquic_log = f.read()
        f.close()

        print(f"xqc_conn_destroy log (P=20): {xquic_log[:500]}")

        # verify the connection was established (xqc_conn_destroy entry expected)
        self.assertGreater(len(xquic_log), 0,
                          "Expected xqc_conn_destroy log output when P=20")

        # extract passive_bidi_s_max value with regex
        match = re.search(r'passive_bidi_s_max:(\d+)', xquic_log)
        self.assertIsNotNone(match, "Expected passive_bidi_s_max field when P=20")

        passive_bidi_s_max = int(match.group(1))
        print(f"Extracted passive_bidi_s_max (P=20) = {passive_bidi_s_max}")

        # verify passive_bidi_s_max equals 20 (matches the -P parameter)
        self.assertEqual(passive_bidi_s_max, 20,
                        f"Expected passive_bidi_s_max=20 when P=20, got {passive_bidi_s_max}")

        print(f"Phase 1 succeeded - passive_bidi_s_max={passive_bidi_s_max}")

        # ========== Phase 2: test -P 21 (should exceed limit) ==========
        print("\n--- Phase 2: test -P 21 (should trigger exceed max_streams_bidi_can_recv error) ---")

        # clear all logs
        os.system("echo '' > logs/error.log")
        os.system("echo '' > logs/xquic.log")
        os.system("echo '' > clog")

        time.sleep(2)

        # run test_client connection test, P=21 means create 21 concurrent streams (exceeds limit)
        cmd = "./test_client -a 127.0.0.1 -p 2081 -u 'https://test.taobao.com/test' -D 1 -b 1 -B 1 -s 10 -P 21 -1 -t 10 2>&1"

        # use Popen instead of run so a stuck process can be handled
        import signal
        process = subprocess.Popen(cmd, shell=True,
                                   stdout=subprocess.PIPE,
                                   stderr=subprocess.PIPE,
                                   universal_newlines=True,
                                   preexec_fn=os.setsid)

        # wait 15 seconds, force terminate if not finished
        try:
            stdout, stderr = process.communicate(timeout=15)
            print(f"Client output (P=21): {stdout[:200]}")
        except subprocess.TimeoutExpired:
            print("Client test timeout (P=21), killing process...")
            # kill the entire process group
            os.killpg(os.getpgid(process.pid), signal.SIGTERM)
            time.sleep(1)
            # force kill if still alive
            try:
                os.killpg(os.getpgid(process.pid), signal.SIGKILL)
            except:
                pass
            print("Process killed due to timeout")
        except Exception as e:
            print(f"Client test exception (P=21): {e}")

        time.sleep(3)

        # check whether "exceed max_streams_bidi_can_recv" error appears in error.log
        f = os.popen("cat logs/error.log | grep 'exceed max_streams_bidi_can_recv'")
        error_log = f.read()
        f.close()

        print(f"Error log (P=21): {error_log[:300] if error_log else 'no exceed error found'}")

        # verify the exceed-limit error is present
        self.assertGreater(len(error_log.strip()), 0,
                          "Expected 'exceed max_streams_bidi_can_recv' in error.log when P=21")

        # also check xquic.log
        f = os.popen("cat logs/xquic.log | grep 'exceed max_streams_bidi_can_recv'")
        xquic_error = f.read()
        f.close()

        if xquic_error:
            print(f"xquic.log also reports the exceed error: {xquic_error[:300]}")

        print(f"\n{sys._getframe().f_code.co_name} success - P=20 and P=21 tests both passed")

    def test_2_max_streams_default_values(self):
        """Test case 2: verify default values when max_streams is not set, then reload to custom values"""
        print("\n=== Test case 2: default configuration + reload test ===")

        # ========== Phase 1: comment out max_streams configuration, test default values ==========
        print("\n--- Phase 1: comment out max_streams configuration, test default values with -P 50 ---")

        # comment out max_streams configuration lines
        os.system("sed -i 's/^\\s*xquic_max_streams_bidi/#&/' conf/nginx_max_streams.conf")
        os.system("sed -i 's/^\\s*xquic_max_streams_uni/#&/' conf/nginx_max_streams.conf")

        # clear logs
        os.system("echo '' > logs/error.log")
        os.system("echo '' > logs/xquic.log")
        os.system("echo '' > clog")

        # start nginx
        self.stop_nginx()
        self.p.start("conf/nginx_max_streams.conf")
        time.sleep(2)

        # run test_client connection test, P=50 creates 50 concurrent streams (verify default is large enough)
        cmd = "./test_client -a 127.0.0.1 -p 2081 -u 'https://test.taobao.com/test' -D 1 -b 1 -B 1 -s 10 -P 50 -1 -t 10 2>&1"

        # use Popen to handle possible timeout
        import signal
        process = subprocess.Popen(cmd, shell=True,
                                   stdout=subprocess.PIPE,
                                   stderr=subprocess.PIPE,
                                   universal_newlines=True,
                                   preexec_fn=os.setsid)

        # wait 15 seconds
        client_output = ""
        try:
            stdout, stderr = process.communicate(timeout=15)
            client_output = stdout
            print(f"Client output (P=50): {stdout[:200]}")
        except subprocess.TimeoutExpired:
            print("Client test timeout (expected)")
            # kill the process group
            os.killpg(os.getpgid(process.pid), signal.SIGTERM)
            time.sleep(1)
            try:
                os.killpg(os.getpgid(process.pid), signal.SIGKILL)
            except:
                pass
            print("Process killed due to timeout")
        except Exception as e:
            print(f"Client test exception: {e}")

        time.sleep(3)

        # count occurrences of ":status = 200" in test_client output
        status_200_count = client_output.count(":status = 200")
        print(f"Found {status_200_count} ':status = 200' in test_client output")

        # expect 50 successful responses
        self.assertGreaterEqual(status_200_count, 50,
                        f"Expected 50 ':status = 200' responses, got {status_200_count}")

        # error.log should NOT contain "exceed max_streams_bidi_can_recv"
        f = os.popen("cat logs/error.log | grep 'exceed max_streams_bidi_can_recv'")
        error_log = f.read()
        f.close()

        # expect no exceed-limit error (default value should be large enough)
        self.assertEqual(len(error_log.strip()), 0,
                        f"Did not expect 'exceed max_streams_bidi_can_recv' error when P=50, but got: {error_log[:200]}")

        print(f"Verification passed: no exceed error when P=50")

        # read xqc_conn_destroy report records from xquic.log
        f = os.popen("cat logs/xquic.log | grep 'xqc_conn_destroy' | grep 'report'")
        xquic_log = f.read()
        f.close()

        # verify the connection was established
        self.assertGreater(len(xquic_log), 0,
                          "Expected xqc_conn_destroy log output")

        # try to extract passive_bidi_s_max for informational display
        match = re.search(r'passive_bidi_s_max:(\d+)', xquic_log)
        if match:
            passive_bidi_s_max = int(match.group(1))
            print(f"Extracted passive_bidi_s_max (default config) = {passive_bidi_s_max}")
            # default config should handle 50 streams
            self.assertGreaterEqual(passive_bidi_s_max, 50,
                                   f"Default passive_bidi_s_max should be >=50, got {passive_bidi_s_max}")
        else:
            print("passive_bidi_s_max field not found (connection may not have closed normally)")

        # ========== Phase 2: restore configuration, reload and test -P 20 ==========
        print("\n--- Phase 2: restore max_streams configuration, reload and test -P 20 ---")

        # restore max_streams configuration lines (uncomment)
        os.system("sed -i 's/^\\s*#\\(\\s*xquic_max_streams_bidi\\)/\\1/' conf/nginx_max_streams.conf")
        os.system("sed -i 's/^\\s*#\\(\\s*xquic_max_streams_uni\\)/\\1/' conf/nginx_max_streams.conf")

        # clear logs
        os.system("echo '' > logs/error.log")
        os.system("echo '' > logs/xquic.log")
        os.system("echo '' > clog")

        # reload configuration
        self.p.reload()
        time.sleep(3)  # wait for reload to complete

        # run test_client with P=20 (should succeed)
        cmd = "./test_client -a 127.0.0.1 -p 2081 -u 'https://test.taobao.com/test' -D 1 -b 1 -B 1 -s 10 -P 20 -1 -t 10 2>&1"

        process = subprocess.Popen(cmd, shell=True,
                                   stdout=subprocess.PIPE,
                                   stderr=subprocess.PIPE,
                                   universal_newlines=True,
                                   preexec_fn=os.setsid)

        client_output_reload = ""
        try:
            stdout, stderr = process.communicate(timeout=15)
            client_output_reload = stdout
            print(f"Client output (reload, P=20): {stdout[:200]}")
        except subprocess.TimeoutExpired:
            print("Client test timeout (expected)")
            os.killpg(os.getpgid(process.pid), signal.SIGTERM)
            time.sleep(1)
            try:
                os.killpg(os.getpgid(process.pid), signal.SIGKILL)
            except:
                pass
            print("Process killed due to timeout")
        except Exception as e:
            print(f"Client test exception: {e}")

        time.sleep(3)

        # count status code 200 (use a more precise match)
        # test_client output format: ":status = 200" with possible extra whitespace
        status_200_matches = re.findall(r':status\s*=\s*200', client_output_reload)
        status_200_count_reload = len(status_200_matches)
        print(f"After reload found {status_200_count_reload} ':status = 200'")

        # expect 20 successful responses (allow tolerance, retries possible during reload)
        self.assertGreaterEqual(status_200_count_reload, 20,
                        f"After reload expected at least 20 ':status = 200' responses, got {status_200_count_reload}")
        self.assertLessEqual(status_200_count_reload, 22,
                        f"After reload expected at most 22 ':status = 200' responses, got {status_200_count_reload}")

        # read xquic.log to verify passive_bidi_s_max
        f = os.popen("cat logs/xquic.log | grep 'xqc_conn_destroy' | grep 'report'")
        xquic_log_reload = f.read()
        f.close()

        match_reload = re.search(r'passive_bidi_s_max:(\d+)', xquic_log_reload)
        if match_reload:
            passive_bidi_s_max_reload = int(match_reload.group(1))
            print(f"After reload passive_bidi_s_max = {passive_bidi_s_max_reload}")
            # verify the reloaded config took effect, expected 20
            self.assertEqual(passive_bidi_s_max_reload, 20,
                           f"After reload expected passive_bidi_s_max=20, got {passive_bidi_s_max_reload}")

        # ========== Phase 3: test -P 21 (should exceed limit) ==========
        print("\n--- Phase 3: after reload test -P 21 (should trigger exceed max_streams_bidi_can_recv error) ---")

        # clear logs
        os.system("echo '' > logs/error.log")
        os.system("echo '' > logs/xquic.log")
        os.system("echo '' > clog")

        time.sleep(2)

        # run test_client with P=21 (should exceed limit)
        cmd = "./test_client -a 127.0.0.1 -p 2081 -u 'https://test.taobao.com/test' -D 1 -b 1 -B 1 -s 10 -P 21 -1 -t 10 2>&1"

        process = subprocess.Popen(cmd, shell=True,
                                   stdout=subprocess.PIPE,
                                   stderr=subprocess.PIPE,
                                   universal_newlines=True,
                                   preexec_fn=os.setsid)

        # wait 15 seconds, force terminate if not finished
        try:
            stdout, stderr = process.communicate(timeout=15)
            print(f"Client output (reload P=21): {stdout[:200]}")
        except subprocess.TimeoutExpired:
            print("Client test timeout (P=21), killing process...")
            # kill the entire process group
            os.killpg(os.getpgid(process.pid), signal.SIGTERM)
            time.sleep(1)
            try:
                os.killpg(os.getpgid(process.pid), signal.SIGKILL)
            except:
                pass
            print("Process killed due to timeout")
        except Exception as e:
            print(f"Client test exception (P=21): {e}")

        time.sleep(3)

        # check whether "exceed max_streams_bidi_can_recv" appears in error.log
        f = os.popen("cat logs/error.log | grep 'exceed max_streams_bidi_can_recv'")
        error_log_p21 = f.read()
        f.close()

        print(f"Error log (reload P=21): {error_log_p21[:300] if error_log_p21 else 'no exceed error found'}")

        # expect the exceed-limit error (proving reloaded config took effect)
        self.assertGreater(len(error_log_p21.strip()), 0,
                          "After reload P=21 expected 'exceed max_streams_bidi_can_recv' in error.log")

        print(f"\n{sys._getframe().f_code.co_name} success - P=50, reload P=20 and reload P=21 tests all passed")



if __name__ == '__main__':
    # run tests
    unittest.main(verbosity=2)
