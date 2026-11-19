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

class TestSiphash(unittest.TestCase):
    p = nginx.Nginx(config.TENGINE)


    @classmethod
    def setUpClass(self):
        os.system("cp -f ../../../libs/xquic/build/tests/test_client ./test_client")
        os.system("chmod +x test_client")
        self.p.start("conf/nginx_siphash_log.conf") 
        time.sleep(1)
    @classmethod
    def tearDownClass(self):
        self.p.stop()

    
    def stop_nginx(self):
        self.p.stop()
        time.sleep(2)

    def test_1_siphash_log(self):
        self.stop_nginx()
        time.sleep(1)
        os.system("echo "" > logs/error.log")
        self.p.start("conf/nginx_siphash_log.conf") 
        time.sleep(1)
        os.system("./test_client -a '127.0.0.1' -p 2445 -D 6 -b 25 -B 25  -t 7 -P 1 2>&1 >/dev/null")
        time.sleep(10)
        f = os.popen("cat logs/error.log | grep xqc_str_hash_add")
        lines = f.readlines()
        #print(lines)
        self.assertEqual(len(lines) > 0, True)
        print("%s success"%(sys._getframe().f_code.co_name))

    def test_2_siphash_default_hash_size(self):
        self.stop_nginx()
        os.system("echo "" > logs/error.log")
        time.sleep(1)
        self.p.start("conf/nginx_siphash_default_hash_size.conf")
        time.sleep(1)
        os.system("./test_client -a '127.0.0.1' -p 2445 -D 6 -b 25 -B 25  -t 7 -P 1 2>&1 >/dev/null")
        time.sleep(10)
        f = os.popen("cat logs/error.log | grep xqc_str_hash_add")
        lines = f.readlines()
        if len(lines) > 0:
            line = lines[0]
            v = line.split("index:")[1].split(",")[0]
            
            self.assertEqual(int(v) >= 128 , True )
        else:
            self.assertEqual(len(lines), 0)
        print("%s success"%(sys._getframe().f_code.co_name))

    def test_3_siphash_default(self):
        os.system("echo "" > logs/error.log")
        self.stop_nginx()
        time.sleep(1)
        self.p.start("conf/nginx_siphash_default.conf")
        time.sleep(1)
        os.system("./test_client -a '127.0.0.1' -p 2445 -D 6 -b 25 -B 25  -t 7 -P 1 2>&1 >/dev/null ")
        time.sleep(10)
        f = os.popen("cat logs/error.log | grep xqc_str_hash_add")
        lines = f.readlines()
        #print(lines)
        self.assertEqual(len(lines) , 0)

        print("%s success"%(sys._getframe().f_code.co_name))

if __name__ == '__main__':
    unittest.main()
