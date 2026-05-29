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

class TestUdpQUIC(unittest.TestCase):
    p = nginx.Nginx(config.TENGINE)


    @classmethod
    def setUpClass(self):
        os.system("cp -f ../../../libs/xquic/build/tests/test_client ./test_client")
        os.system("chmod +x test_client")
        os.system("rm logs/error.log")
        self.p.start("conf/nginx_multipath_quic.conf") 
        time.sleep(1)

    @classmethod
    def tearDownClass(self):
        self.p.stop()

    
    def stop_nginx(self):
        self.p.stop()
        time.sleep(2)

    def test_1_udp_quic(self):
        os.system("./test_client -T 1 -a '127.0.0.1' -p 2445 -h 'gateway.instagram.com' -1 2>&1 >/dev/null")
        time.sleep(2)
        f = os.popen("cat logs/error.log | grep 'xqc_ssl_alpn_select_cb' | grep 'select proto error' ")
        lines = f.readlines()
        self.assertEqual(len(lines) > 0, True)

        print("%s success"%(sys._getframe().f_code.co_name))

if __name__ == '__main__':
    unittest.main()
