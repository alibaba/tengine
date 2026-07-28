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

#
#class TestReusesportXudp(unittest.TestCase):
#    p = nginx.Nginx(config.TENGINE)
#    uri = "/h5/"
#    host = "acs.waptest.taobao.com"
#    tcp_port = 2080
#    udp_port = 2081
#    @classmethod
#    def setUpClass(self):
#        os.system("cp -f ../../../libs/xquic/build/tests/test_client ./test_client")
#        os.system("chmod +x test_client")
#        self.p.start("conf/nginx_reuseport_xudp.conf") 
#        time.sleep(4)
#
#    @classmethod
#    def tearDownClass(self):
#        os.system("rm -f clog")
#        self.p.stop()
#
# 
#    def stop_nginx(self):
#        self.p.stop()
#        time.sleep(2)
#
#    def reload_nginx(self):
#        self.p.reload()
#        time.sleep(1)
#    
#    def get_nginx_pid(self):
#        cmd = "ps axu | grep nginx | grep worker | grep -v grep | awk -F ' ' '{print $2}'"
#        res = subprocess.Popen(cmd,shell=True,stdout=subprocess.PIPE,stderr=subprocess.PIPE)
#        stdout,stderr = res.communicate()
#        pids = stdout.splitlines()
#        pid_list = []
#        for pid in pids:
#            pid_list.append(pid.decode())
#        return pid_list
#
#    def restart_nginx(self):
#        self.p.stop()
#        time.sleep(1)
#        self.p.start("conf/nginx_reuseport_xudp.conf")
#        time.sleep(5)
# 
#
#    def get_pid_from_lines(self, lines):
#        pid_dict = {}
#        count = 0
#        for line in lines:
#            if isinstance(line,bytes):
#                line = line.decode()
#            if "current-pid" in line:
#                pid = line.split("=")[1].strip()
#                if pid in list(pid_dict.keys()):
#                    pid_dict[pid] += 1
#                else:
#                    pid_dict[pid] = 1
#                count += 1
#        return (count, pid_dict)
#    
#
#    def test_1_h3_reuseport_load_balance_xudp(self):
#        cmd = "./test_client  -a '127.0.0.1' -p 2081 -D 1 -b 20 -B 200 -t 3 -u 'https://acs.waptest.taobao.com/h5/' " 
#        res = subprocess.Popen(cmd,shell=True,stdout=subprocess.PIPE,stderr=subprocess.PIPE)
#        stdout, stderr = res.communicate()
#        lines = stdout.splitlines()
#        pid_dict = {}
#        count = 0
#        for line in lines:
#            if isinstance(line,bytes):
#                line = line.decode()
#            if "current-pid" in line:
#                pid = line.split("=")[1].strip()
#                if pid in list(pid_dict.keys()):
#                    pid_dict[pid] += 1
#                else:
#                    pid_dict[pid] = 1
#                count += 1
#        
#        self.assertGreaterEqual(count, 200)
#        self.assertLessEqual(count, 203) 
#        for pk in list(pid_dict.keys()):
#            self.assertGreaterEqual(pid_dict[pk], 35)
#            self.assertLessEqual(pid_dict[pk], 65)
#        print("%s success"%(sys._getframe().f_code.co_name))
#    
#    def test_2_h3_reuseport_reload_xudp(self):
#        self.restart_nginx()
#        pids = self.get_nginx_pid() 
#        cmd = "./test_client  -a '127.0.0.1' -p 2081 -D 1 -b 1 -B 1 -t 60 -P 50 -S 1 -u 'https://acs.waptest.taobao.com/h5/' "
#        res = subprocess.Popen(cmd,shell=True,stdout=subprocess.PIPE,stderr=subprocess.PIPE)
#        #print(time.strftime('%Y-%m-%d %H:%M:%S', time.localtime(time.time())))
#        self.reload_nginx()
#        #print(time.strftime('%Y-%m-%d %H:%M:%S', time.localtime(time.time())))
#        stdout, stderr = res.communicate()
#        lines = stdout.splitlines()
#        (count, pid_dict) = self.get_pid_from_lines(lines)
#        self.assertGreaterEqual(count, 49)
#        self.assertLessEqual(count, 52)
#        self.assertEqual(len(pid_dict.keys()), 1)
#        self.assertIn(list(pid_dict.keys())[0], pids)
#        print("%s success"%(sys._getframe().f_code.co_name))
#
#    def test_3_multipath_xudp(self):
#        # primary path network migration
#        cmd = " ./test_client -a '127.0.0.1' -p 2445 -s 102400 -l d -t 3 -M -i lo -i lo -x 103 -n 100 -E -u 'https://acs.waptest.taobao.com/h5/' "
#        self.restart_nginx()
#        pids = self.get_nginx_pid() 
#        res = subprocess.Popen(cmd,shell=True,stdout=subprocess.PIPE,stderr=subprocess.PIPE)
#        stdout, stderr = res.communicate()
#        lines = stdout.splitlines()
#        (count, pid_dict) = self.get_pid_from_lines(lines)
#        self.assertEqual(count, 100)
#        self.assertEqual(len(pid_dict.keys()), 1)
#        self.assertIn(list(pid_dict.keys())[0], pids)
#
#        # secondary path network migration
#        cmd = "./test_client -a '127.0.0.1' -p 2445 -s 102400 -l d -t 3 -M -i lo -i lo -x 104 -n 100 -E -u 'https://acs.waptest.taobao.com/h5/' "
#        res = subprocess.Popen(cmd,shell=True,stdout=subprocess.PIPE,stderr=subprocess.PIPE)
#        stdout, stderr = res.communicate()
#        lines = stdout.splitlines()
#        (count, pid_dict) = self.get_pid_from_lines(lines)
#        self.assertEqual(count, 100)
#
#        # primary path closed
#        cmd = "./test_client -a '127.0.0.1' -p 2445 -s 102400 -l d -t 3 -M -i lo -i lo -x 105 -n 100 -E -u 'https://acs.waptest.taobao.com/h5/' "
#        res = subprocess.Popen(cmd,shell=True,stdout=subprocess.PIPE,stderr=subprocess.PIPE)
#        stdout, stderr = res.communicate()
#        lines = stdout.splitlines()
#        (count, pid_dict) = self.get_pid_from_lines(lines)
#        self.assertEqual(count, 100)
# 
#
#        # secondary path closed
#        cmd = "./test_client -a '127.0.0.1' -p 2445 -s 102400 -l d -t 3 -M -i lo -i lo -x 106 -n 100 -E -u 'https://acs.waptest.taobao.com/h5/' "
#        res = subprocess.Popen(cmd,shell=True,stdout=subprocess.PIPE,stderr=subprocess.PIPE)
#        stdout, stderr = res.communicate()
#        lines = stdout.splitlines()
#        (count, pid_dict) = self.get_pid_from_lines(lines)
#        self.assertEqual(count, 100)
# 
#        print("%s success"%(sys._getframe().f_code.co_name))
#  
#    def get_output_when_reload(self, cmd):
#        res = subprocess.Popen(cmd,shell=True,stdout=subprocess.PIPE,stderr=subprocess.PIPE)
#        self.reload_nginx()
#        stdout, stderr = res.communicate()
#        lines = stdout.splitlines()
#        return lines
#
#    def test_4_multipath_reload_xudp(self):
#        # primary path migration
#        self.restart_nginx()
#        pids = self.get_nginx_pid() 
#        cmd = " ./test_client -a '127.0.0.1' -p 2445 -s 1024000 -l d -t 3 -M -i lo -i lo -x 103 -n 100 -E -u 'https://acs.waptest.taobao.com/h5/' "
#        lines = self.get_output_when_reload(cmd)
#        (count, pid_dict) = self.get_pid_from_lines(lines)
#        self.assertEqual(count, 100)
#        self.assertEqual(len(pid_dict.keys()), 1)
#        self.assertIn(list(pid_dict.keys())[0], pids)
#
#        # secondary path network migration
#        self.restart_nginx()
#        pids = self.get_nginx_pid()
#        cmd = "./test_client -a '127.0.0.1' -p 2445 -s 1024000 -l d -t 3 -M -i lo -i lo -x 104 -n 100 -E -u 'https://acs.waptest.taobao.com/h5/' "
#        lines = self.get_output_when_reload(cmd)
#        (count, pid_dict) = self.get_pid_from_lines(lines)
#        self.assertEqual(count, 100)
#        self.assertEqual(len(pid_dict.keys()), 1)
#        self.assertIn(list(pid_dict.keys())[0], pids)
#
#        # primary path closed
#        cmd = "./test_client -a '127.0.0.1' -p 2445 -s 102400 -l d -t 3 -M -i lo -i lo -x 105 -n 100 -E -u 'https://acs.waptest.taobao.com/h5/' "
#        self.restart_nginx()
#        pids = self.get_nginx_pid()
#        lines = self.get_output_when_reload(cmd)
#        (count, pid_dict) = self.get_pid_from_lines(lines)
#        self.assertEqual(count, 100)
#        self.assertEqual(len(pid_dict.keys()), 1)
#        self.assertIn(list(pid_dict.keys())[0], pids)
#
#
#        # secondary path closed
#        cmd = "./test_client -a '127.0.0.1' -p 2445 -s 102400 -l d -t 3 -M -i lo -i lo -x 106 -n 100 -E -u 'https://acs.waptest.taobao.com/h5/' "
#        self.restart_nginx()
#        pids = self.get_nginx_pid()
#        lines = self.get_output_when_reload(cmd)
#        (count, pid_dict) = self.get_pid_from_lines(lines)
#        self.assertEqual(count, 100)
#        self.assertEqual(len(pid_dict.keys()), 1)
#        self.assertIn(list(pid_dict.keys())[0], pids)
#
#        print("%s success"%(sys._getframe().f_code.co_name))

if __name__ == '__main__':
    unittest.main()
