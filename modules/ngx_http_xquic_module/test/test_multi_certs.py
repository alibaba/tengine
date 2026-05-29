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
        os.system("chmod +x test_client")
        self.p.start("conf/nginx_multi_certs.conf") 
        time.sleep(1)

    @classmethod
    def tearDownClass(self):
        self.p.stop()

    def stop_nginx(self):
        self.p.stop()
        time.sleep(2)


    def test_multi_certs_single_server(self):
        os.system("echo "" > logs/error.log")
        os.system("echo "" > logs/xquic.log")
        os.system("echo "" > logs/std.log")

        # single server block
        os.system("rm -f test_session")
        os.system("./test_client -a '127.0.0.1' -p 2081 -G -u \"https://test.multicert1.com/gw/gettest\" -V 1 > logs/std.log ")
        f = os.popen("cat logs/std.log | grep 'request time cost' ")
        lines = f.readlines()
        self.assertEqual(len(lines) > 0, True)
        print("%s success"%(sys._getframe().f_code.co_name))



    def test_multi_certs_fuzzy_match_first(self):
        os.system("echo "" > logs/error.log")
        os.system("echo "" > logs/xquic.log")
        os.system("echo "" > logs/std.log")

        # multiple server block, request for first
        os.system("rm -f test_session")
        os.system("./test_client -a '127.0.0.1' -p 3081 -G -u \"https://test.multicert1.com/gw/gettest\" -V 1 > logs/std.log ")
        f = os.popen("grep \">>>>>>>>\" logs/std.log")
        lines = f.readlines()
        self.assertEqual(len(lines) > 0, True)
        print("%s success"%(sys._getframe().f_code.co_name))



    def test_multi_certs_fuzzy_match_second(self):
        os.system("echo "" > logs/error.log")
        os.system("echo "" > logs/xquic.log")
        os.system("echo "" > logs/std.log")

        # multiple server block, request for second
        os.system("rm -f test_session")
        os.system("./test_client -a '127.0.0.1' -p 3081 -G -u \"https://test.multicert2.com/gw/gettest\" -V 1 > logs/std.log ")
        f = os.popen("grep \">>>>>>>>\" logs/std.log")
        lines = f.readlines()
        self.assertEqual(len(lines) > 0, True)
        print("%s success"%(sys._getframe().f_code.co_name))



    def test_multi_certs_fuzzy_sni_match_first(self):
        os.system("echo "" > logs/error.log")
        os.system("echo "" > logs/xquic.log")
        os.system("echo "" > logs/std.log")

        # multiple server block, request for first
        os.system("rm -f test_session")
        os.system("./test_client -a '127.0.0.1' -p 3082 -G -u \"https://multicert1.com/gw/gettest\" > logs/std.log ")
        f = os.popen("grep \">>>>>>>>\" logs/std.log")
        lines = f.readlines()
        self.assertEqual(len(lines) > 0, True)
        print("%s success"%(sys._getframe().f_code.co_name))



    def test_multi_certs_fuzzy_sni_match_second(self):
        os.system("echo "" > logs/error.log")
        os.system("echo "" > logs/xquic.log")
        os.system("echo "" > logs/std.log")

        # multiple server block, request for second
        os.system("rm -f test_session")
        os.system("./test_client -a '127.0.0.1' -p 3082 -G -u \"https://multicert2.com/gw/gettest\" > logs/std.log ")
        f = os.popen("grep \">>>>>>>>\" logs/std.log")
        lines = f.readlines()
        self.assertEqual(len(lines) > 0, True)
        print("%s success"%(sys._getframe().f_code.co_name))


#    def test_multi_certs_duplicate_keyless_certs(self):
#        os.system("echo "" > logs/error.log")
#        os.system("echo "" > logs/xquic.log")
#        os.system("echo "" > logs/std.log")
#
#        # test with openssl s_client
#        os.system("rm -f test_session")
#        os.system("openssl s_client -showcerts -connect 127.0.0.1:4081 <<< \"Q\" > logs/std.log ")
#        f = os.popen("grep \"BEGIN CERTIFICATE\" logs/std.log")
#        lines = f.readlines()
#        self.assertEqual(len(lines), 1)
#        print("%s success"%(sys._getframe().f_code.co_name))


if __name__ == '__main__':
    unittest.main()
