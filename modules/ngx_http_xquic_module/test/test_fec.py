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
import re

class TestFEC(unittest.TestCase):
    p = nginx.Nginx(config.TENGINE)


    @classmethod
    def setUpClass(self):
        os.system("cp -f ../../../libs/xquic/build/tests/test_client ./test_client")
        os.system("chmod +x test_client")
        self.p.start("conf/nginx_fec.conf") 
        time.sleep(1)

    @classmethod
    def tearDownClass(self):
        self.p.stop()

    
    def stop_nginx(self):
        self.p.stop()
        time.sleep(2)

    def get_fec_info(self, lines):
        fec_encode = 0
        fec_decode = 0
        fec_process_block = 0
        fec_recv_repair = 0

        for line in lines:
            pattern = r'"fec"\s*:\s*"([^"]*)"'
            match = re.search(pattern, line)

            if match:
                fec_value = match.group(1)
                # strip strings
                values = fec_value.split(',')

                # get two values
                if len(values) >= 2:
                    return (values[0], values[1])

        return (None, None)


    def test_fec_negotiation(self):
        os.system("echo "" > logs/error.log")
        os.system("echo "" > logs/xquic.log")
        os.system("echo "" > logs/std.log")

        os.system("rm -f test_session")
        os.system("./test_client -a '127.0.0.1' -p 2445 -s 1024000 -l d -g > logs/std.log")
        time.sleep(2)
        f = os.popen("cat logs/xquic.log | grep 'xqc_conn_destroy' ")
        lines = f.readlines()
        print(lines)
        (fec_encode, fec_decode) = self.get_fec_info(lines)
        self.assertEqual(int(fec_encode), 1)
        self.assertEqual(int(fec_decode), 1)
        print("%s success"%(sys._getframe().f_code.co_name))


if __name__ == '__main__':
    unittest.main()
