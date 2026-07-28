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
import socket

class TestUdpHealthCheck(unittest.TestCase):
    p = nginx.Nginx(config.TENGINE)


    @classmethod
    def setUpClass(self):
        self.p.start("conf/nginx_udp_health_check.conf") 
        time.sleep(1)

    @classmethod
    def tearDownClass(self):
        self.p.stop()
        time.sleep(2)
        print("killall nginx")
        os.system("killall nginx")

    
    def stop_nginx(self):
        self.p.stop()
        time.sleep(2)

    def test_1_udp_ok(self):
        # create UDP socket
        sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)

        try:
            # message to send
            message = 'UDPSTATUS'
            # send message to UDP server
            sock.sendto(message.encode(), ('127.0.0.1', 2445))

            # set a reasonable timeout to avoid blocking too long on recv
            sock.settimeout(2)

            resp = None

            try:
                # receive response from UDP server
                data, server = sock.recvfrom(4096)
                resp = data.decode()
            except socket.timeout:
                pass

        finally:
            # close socket
            sock.close()

        self.assertEqual(resp == 'UDPOK', True)

        print("%s success"%(sys._getframe().f_code.co_name))

    def test_1_udp_no_resp(self):
        # remove health check file
        os.system("rm -f ./htdocs/status.taobao")
        # create UDP socket
        sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)

        try:
            # message to send
            message = 'UDPSTATUS'
            # send message to UDP server
            sock.sendto(message.encode(), ('127.0.0.1', 2445))

            # set a reasonable timeout to avoid blocking too long on recv
            sock.settimeout(2)

            resp = None

            try:
                # receive response from UDP server
                data, server = sock.recvfrom(4096)
                resp = data.decode()
            except socket.timeout:
                pass

        finally:
            # close socket
            sock.close()

        # restore health check file
        os.system("touch ./htdocs/status.taobao")

        self.assertEqual(resp == None, True)

        print("%s success"%(sys._getframe().f_code.co_name))


if __name__ == '__main__':
    unittest.main()
