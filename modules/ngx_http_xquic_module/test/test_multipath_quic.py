#!/usr/bin/env python
# encoding: utf-8

import unittest
import os
import requests
import time
import sys
sys.path.append("../../../tests/unittest_pycommon")
import config
import nginx

class TestCC(unittest.TestCase):
    p = nginx.Nginx(config.TENGINE)


    @classmethod
    def setUpClass(self):
        os.system("cp -f ../../../libs/xquic/build/tests/test_client ./test_client")
        os.system("rm -f tp_localhost  xqc_token")
        os.system("chmod +x test_client")
        self.p.start("conf/nginx_multipath_quic.conf") 
        time.sleep(1)

    @classmethod
    def tearDownClass(self):
        self.p.stop()

    
    def stop_nginx(self):
        self.p.stop()
        time.sleep(2)

    def test_1_multipath(self):
        os.system("./test_client -a '127.0.0.1' -p 2445 -s 1024000 -l d -t 3 -M -i lo -i lo -E 2>&1 >/dev/null")
        time.sleep(2)
        f = os.popen("cat logs/xquic.log | grep 'xqc_conn_destroy' | grep 'mp_enable:1' ")
        lines = f.readlines()
        self.assertEqual(len(lines) > 0, True)

        print("%s success"%(sys._getframe().f_code.co_name))

    def test_1_multipath_path_0_NAT_rebinding(self):
        os.system("echo "" > logs/xquic.log")
        os.system("echo "" > logs/error.log")

        os.system("./test_client -a '127.0.0.1' -p 2445 -s 102400 -l d -t 3 -M -i lo -i lo -x 103 -n 2 -E 2>&1 >/dev/null")
        f = os.popen("cat logs/error.log | grep '|xquic|ngx_xquic_conn_peer_addr_changed_notify|' ")
        lines = f.readlines()
        self.assertEqual(len(lines) > 0, True)

        print("%s success"%(sys._getframe().f_code.co_name))

    def test_1_multipath_path_1_NAT_rebinding(self):
        os.system("echo "" > logs/xquic.log")
        os.system("echo "" > logs/error.log")

        os.system("./test_client -a '127.0.0.1' -p 2445 -s 102400 -l d -t 3 -M -i lo -i lo -x 104 -n 2 -E 2>&1 >/dev/null")
        f = os.popen("cat logs/error.log | grep '|xquic|ngx_xquic_path_peer_addr_changed_notify|' ")
        lines = f.readlines()
        self.assertEqual(len(lines) > 0, True)

        print("%s success"%(sys._getframe().f_code.co_name))

    def test_1_multipath_path_0_close(self):
        os.system("echo "" > logs/xquic.log")
        os.system("echo "" > logs/error.log")

        os.system("./test_client -a '127.0.0.1' -p 2445 -s 102400 -l d -t 5 -M -i lo -i lo -E -x 100 -e 10 --epoch_timeout 1000000 2>&1 >/dev/null")
        f = os.popen("cat logs/error.log | grep '|xquic|ngx_xquic_path_removed_notify|path=0|' ")
        lines = f.readlines()
        self.assertEqual(len(lines) > 0, True)

        print("%s success"%(sys._getframe().f_code.co_name))

    def test_1_multipath_path_1_close(self):
        os.system("echo "" > logs/xquic.log")
        os.system("echo "" > logs/error.log")

        os.system("./test_client -a '127.0.0.1' -p 2445 -s 10240 -l d -t 5 -M -A -i lo -i lo -E -x 101 -e 10 --epoch_timeout 1000000 2>&1 >/dev/null")
        f = os.popen("cat logs/error.log | grep '|xquic|ngx_xquic_path_removed_notify|path=1|' ")
        lines = f.readlines()
        self.assertEqual(len(lines) > 0, True)

        print("%s success"%(sys._getframe().f_code.co_name))


if __name__ == '__main__':
    unittest.main()
