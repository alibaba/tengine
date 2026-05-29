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
import subprocess

#class TestQlog(unittest.TestCase):
#    p = nginx.Nginx(config.TENGINE)
#
#
#    @classmethod
#    def setUpClass(self):
#        os.system("cp -f ../../../libs/xquic/build/tests/test_client ./test_client")
#        os.system("chmod +x test_client")
#        self.p.start("conf/nginx_qlog.conf")
#        time.sleep(1)
#
#    @classmethod
#    def tearDownClass(self):
#        self.p.stop()
#
#    
#    def stop_nginx(self):
#        self.p.stop()
#        time.sleep(2)
#
#    def test_qlog_enable(self):
#        os.system("./test_client -a '127.0.0.1' -p 2445 -s 1024000 -l d -t 3 -M -i lo -i lo -E 2 -g 2>&1 >/dev/null")
#        time.sleep(2)
#        lines = subprocess.check_output("cat logs/error.log | grep 'xquic|qlog' ", shell=True)
#        #print(lines)
#        self.assertEqual(len(lines) > 0, True)
#        print("%s success"%(sys._getframe().f_code.co_name))
#        os.system("echo "" > logs/xquic.log")
#        os.system("echo "" > logs/error.log")


if __name__ == '__main__':
    unittest.main()
