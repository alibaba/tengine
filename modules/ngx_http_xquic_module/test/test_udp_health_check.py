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
        # 创建UDP套接字
        sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)

        try:
            # 要发送的消息
            message = 'UDPSTATUS'
            # 发送消息到UDP服务器
            sock.sendto(message.encode(), ('127.0.0.1', 2445))

            # 设置一个合理的超时时间，以免接收阻塞太久
            sock.settimeout(2)

            resp = None

            try:
                # 接收UDP服务器的响应
                data, server = sock.recvfrom(4096)
                resp = data.decode()
            except socket.timeout:
                pass

        finally:
            # 关闭套接字
            sock.close()

        self.assertEqual(resp == 'UDPOK', True)

        print("%s success"%(sys._getframe().f_code.co_name))

    def test_1_udp_no_resp(self):
        # 删除健康检查文件
        os.system("rm -f ./htdocs/status.taobao")
        # 创建UDP套接字
        sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)

        try:
            # 要发送的消息
            message = 'UDPSTATUS'
            # 发送消息到UDP服务器
            sock.sendto(message.encode(), ('127.0.0.1', 2445))

            # 设置一个合理的超时时间，以免接收阻塞太久
            sock.settimeout(2)

            resp = None

            try:
                # 接收UDP服务器的响应
                data, server = sock.recvfrom(4096)
                resp = data.decode()
            except socket.timeout:
                pass

        finally:
            # 关闭套接字
            sock.close()

        # 恢复健康检查文件
        os.system("touch ./htdocs/status.taobao")

        self.assertEqual(resp == None, True)

        print("%s success"%(sys._getframe().f_code.co_name))


if __name__ == '__main__':
    unittest.main()
