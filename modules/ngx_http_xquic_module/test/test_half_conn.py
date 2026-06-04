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
def get_local_ipv4():
    ip_list = []
    p = os.popen("""ifconfig | grep inet | awk -F " " '{print $2}' | grep -v ":" """)

    lines = p.readlines()
    for line in lines:
        ip_list.append(line)
    
    if len(ip_list) == 0:
        ip_list.append("127.0.0.1")

    p.close()
    return ip_list

def get_local_ipv6():
    ip_list = []
    p = os.popen("""ifconfig | grep inet6 | awk -F " " '{print $2}'""")

    lines = p.readlines()
    for line in lines:
        if ":" in line:
            line = line.strip()
            if line == "::1" or line[0:2] == "fe":
                continue
            ip_list.append(line)


    p.close()
    return ip_list

class TestHalfConf(unittest.TestCase):
    p = nginx.Nginx(config.TENGINE)
    ip_list = get_local_ipv4()
    ipv6_list = get_local_ipv6()

    @classmethod
    def setUpClass(self):
        os.system("cp -f ../../../libs/xquic/build/tests/test_client ./test_client")
        os.system("chmod +x test_client")
    @classmethod
    def tearDownClass(self):
        self.p.stop()
    
    def stop_nginx(self):
        self.p.stop()
        time.sleep(2)
    
    
    def test_0_always_retry_packet(self):
        os.system("killall nginx")
        time.sleep(1)
        self.p.start("conf/nginx_always_retry.conf")
        time.sleep(1)
        os.system("echo "" > logs/error.log")
        os.system("rm -f xqc_token")
        os.system("./test_client -T 0 -a '%s' -p 2445 -D 1 -b 1 -B 10 -t 10 2>&1 >/dev/null"%self.ip_list[0])
        f = os.popen("cat logs/error.log | grep xqc_conn_send_retry")
        lines = f.readlines()
        self.assertEqual(len(lines), 10)
        f.close()
        print("%s success"%(sys._getframe().f_code.co_name))

    def test_1_cps_half_conn(self):
        self.p.stop()
        time.sleep(1)
        self.p.start("conf/nginx_half_conn_defense_cps.conf") 
        time.sleep(1)
        
        os.system("echo "" > logs/error.log")
        os.system("rm -f xqc_token")
        os.system("./test_client -T 0 -a '%s' -p 2445 -D 1 -b 1 -B 10 -t 10 2>&1 >/dev/null"%self.ip_list[0])
        f = os.popen("cat logs/error.log | grep xqc_conn_send_retry")
        lines = f.readlines()
        self.assertEqual(len(lines), 0)
        f.close()

        os.system("echo "" > logs/error.log")
        os.system("rm -f xqc_token")
        os.system("./test_client -T 0 -a '%s' -p 2445 -D 1 -b 5 -B 9 -t 10 2>&1 >/dev/null"%self.ip_list[0])
        f = os.popen("cat logs/error.log | grep 'half conn'|grep 'ip exceed threshold' ")   
        lines = f.readlines()
        self.assertEqual(len(lines) > 0, True)
        f.close()

        print("%s success"%(sys._getframe().f_code.co_name))

    def test_2_cps_max_threshold_half_conn(self):
        self.p.stop()
        time.sleep(1)
        self.p.start("conf/nginx_half_conn_defense_cps.conf")
        time.sleep(1)
        os.system("echo "" > logs/error.log")
        os.system("rm -f xqc_token")
        os.system("./test_client -T 0 -a '%s' -p 2445 -D 1 -b 10 -B 30 -t 10 2>&1 >/dev/null &"%self.ip_list[0])
        os.system("rm -f xqc_token")
        os.system("./test_client -T 0 -a '%s' -p 2445 -D 1 -b 10 -B 30 -t 10 2>&1 >/dev/null"%self.ip_list[-1])
        f = os.popen("cat logs/error.log | grep 'half conn attack' | grep 'total connection' ")   
        lines = f.readlines()
        self.assertEqual(len(lines) > 0, True)
        f.close()
        
        print("%s success"%(sys._getframe().f_code.co_name))

    def test_3_conn_half_conn(self):
        self.p.stop()
        time.sleep(1)
        self.p.start("conf/nginx_half_conn_defense.conf")
        time.sleep(1)
        os.system("echo "" > logs/error.log")
        os.system("rm -f xqc_token")
        os.system("./test_client -T 0 -a '%s' -p 2445 -D 1 -b 1 -B 9 -t 10 2>&1 >/dev/null"%self.ip_list[0])
        f = os.popen("cat logs/error.log | grep 'half conn' | grep 'ip exceed threshold'")   
        lines = f.readlines()
        self.assertEqual(len(lines) == 0, True)
        f.close()
        
        os.system("echo "" > logs/error.log")
        os.system("rm -f xqc_token")
        os.system("./test_client -T 0 -a '%s' -p 2445 -D 1 -b 2 -B 9 -t 10 2>&1 >/dev/null"%self.ip_list[0])

        f = os.popen("cat logs/error.log | grep 'half conn' |grep 'ip exceed threshold' ")   
        lines = f.readlines()
        self.assertEqual(len(lines) > 0, True)
        f.close()

        print("%s success"%(sys._getframe().f_code.co_name))

    def test_4_conn_max_threshold_half_conn(self):
        self.p.stop()
        time.sleep(1)
        self.p.start("conf/nginx_half_conn_defense.conf")
        time.sleep(1)
        os.system("echo "" > logs/error.log")
        
        os.system("rm -f xqc_token")
        os.system("./test_client -T 0 -a '%s' -p 2445 -D 1 -b 2 -B 9 -t 10 2>&1 >/dev/null &"%self.ip_list[0])
        os.system("rm -f xqc_token")
        os.system("./test_client -T 0 -a '%s' -p 2445 -D 1 -b 1 -B 9 -t 10 2>&1 >/dev/null "%self.ip_list[-1])

        f = os.popen("cat logs/error.log | grep 'half conn'| grep 'total connection'")
 
        lines = f.readlines()
        self.assertEqual(len(lines) > 0, True)
        f.close()
        
        print("%s success"%(sys._getframe().f_code.co_name))

    def test_5_conn_test_draft_29_not_send_retry(self):
        self.p.stop()
        time.sleep(1)
        self.p.start("conf/nginx_half_conn_defense.conf")
        time.sleep(1)
        os.system("echo "" > logs/error.log")
        
        os.system("rm -f xqc_token")
        os.system("./test_client -T 0 -a '%s' -p 2445 -x 17 -D 1 -b 2 -B 9 -t 10 2>&1 >/dev/null &"%self.ip_list[0])
        os.system("rm -f xqc_token")
        os.system("./test_client -T 0 -a '%s' -p 2445 -x 17 -D 1 -b 1 -B 9 -t 10 2>&1 >/dev/null "%self.ip_list[-1])

        f = os.popen("cat logs/error.log | grep 'half conn'| grep 'total connection'")
 
        lines = f.readlines()
        self.assertEqual(len(lines) , 0)
        f.close()
        
        print("%s success"%(sys._getframe().f_code.co_name))


    def test_6_check_token_encrypt_and_decrypt(self):
        self.p.stop()
        time.sleep(1)
        self.p.start("conf/nginx_always_retry.conf")
        time.sleep(1)
        os.system("rm -f xqc_token test_session ")
        os.system("echo '' > logs/error.log")
        os.system("./test_client -T 0 -a '%s' -p 2445 -t 2 2>&1 >/dev/null"%self.ip_list[0])
        f = os.popen("cat logs/error.log | grep 'check_token fail'")
        lines = f.readlines()
        self.assertEqual(len(lines), 1)
        f.close()

        time.sleep(3)
        os.system("echo '' > logs/error.log")
        os.system("./test_client -T 0 -a '%s' -p 2445 -t 2 2>&1 >/dev/null"%self.ip_list[0])
        f = os.popen("cat logs/error.log | grep 'check_token fail'")
        lines = f.readlines()
        self.assertEqual(len(lines), 0)
        f.close()

        #ipv6
        if len(self.ipv6_list) != 0:
            os.system("echo '' > logs/error.log")
            os.system("./test_client -T 0 -6 -a '%s' -p 2445 -t 2 2>&1 >/dev/null"%self.ipv6_list[0])
            f = os.popen("cat logs/error.log | grep 'check_token fail'")
            lines = f.readlines()
            self.assertEqual(len(lines), 1)
            f.close()
            
            time.sleep(3)
            os.system("echo '' > logs/error.log")
            os.system("./test_client -T 0 -6 -a '%s' -p 2445 -t 2 2>&1 >/dev/null"%self.ipv6_list[0])
            f = os.popen("cat logs/error.log | grep 'check_token fail'")
            lines = f.readlines()
            self.assertEqual(len(lines), 0)
            f.close()
 
        print("%s success"%(sys._getframe().f_code.co_name))
    
    def test_7_check_token_set_token_key_diff(self):
        self.p.stop()
        time.sleep(1)
        self.p.start("conf/nginx_always_retry.conf")
        time.sleep(1)
        os.system("rm -f xqc_token test_session ")
        os.system("echo '' > logs/error.log")
        os.system("./test_client -T 0 -a '%s' -p 2445 -t 2 2>&1 >/dev/null"%self.ip_list[0])
        f = os.popen("cat logs/error.log | grep 'check_token fail'")
        lines = f.readlines()
        self.assertEqual(len(lines), 1)
        f.close()

        self.p.stop()
        time.sleep(1)

        self.p.start("conf/nginx_half_conn_defense.conf")
        time.sleep(1)
        os.system("echo "" > logs/error.log")
        
        os.system("./test_client -T 0 -a '%s' -p 2445 -t 2 2>&1 >/dev/null"%self.ip_list[0])
        f = os.popen("cat logs/error.log | grep 'check_token fail'")
        lines = f.readlines()
        self.assertEqual(len(lines), 1)
        f.close()
        
        self.p.stop()
        time.sleep(1)
        self.p.start("conf/nginx_one_token_key_version.conf")
        time.sleep(1)
        os.system("echo '' > logs/error.log")
        os.system("./test_client -T 0 -a '%s' -p 2445 -t 2 2>&1 >/dev/null"%self.ip_list[0])
        f = os.popen("cat logs/error.log | grep 'check_token fail'")
 
        lines = f.readlines()
        self.assertEqual(len(lines), 1)
        f.close()

        print("%s success"%(sys._getframe().f_code.co_name))
    
    
    def test_8_check_rotating_token_key_with_multi_version(self):
        self.p.stop()
        time.sleep(1)
        self.p.start("conf/nginx_half_conn_defense.conf")
        time.sleep(1)
        os.system("rm -f xqc_token test_session ")
        os.system("echo '' > logs/error.log")
        os.system("./test_client -T 0 -a '%s' -p 2445 -t 2 2>&1 >/dev/null"%self.ip_list[0])
        f = os.popen("cat logs/error.log | grep 'check_token fail'")
        lines = f.readlines()
        f.close()
        self.assertEqual(len(lines), 1)
        f.close()
        
        self.p.stop()
        time.sleep(1)
        self.p.start("conf/nginx_one_token_key_version.conf")
        time.sleep(1)
        os.system("echo '' > logs/error.log")
        os.system("./test_client -T 0 -a '%s' -p 2445 -t 2 2>&1 >/dev/null"%self.ip_list[0])
        f = os.popen("cat logs/error.log | grep 'check_token fail'")
 
        lines = f.readlines()
        self.assertEqual(len(lines), 1)
        f.close()

        #multi token version include all token key
        self.p.stop()
        time.sleep(1)
        self.p.start("conf/nginx_multi_token_key_version.conf")
        time.sleep(1)
        os.system("echo '' > logs/error.log")
        os.system("./test_client -T 0 -a '%s' -p 2445 -t 2 2>&1 >/dev/null"%self.ip_list[0])
        f = os.popen("cat logs/error.log | grep 'check_token fail'")
        lines = f.readlines()
        self.assertEqual(len(lines), 0)
        f.close()

        self.p.stop()
        time.sleep(1)
        self.p.start("conf/nginx_half_conn_defense.conf")
        time.sleep(1)
        os.system("rm -f xqc_token")
        os.system("echo '' > logs/error.log")
        os.system("./test_client -T 0 -a '%s' -p 2445 -t 2 2>&1 >/dev/null"%self.ip_list[0])
        f = os.popen("cat logs/error.log | grep 'check_token fail'")
        lines = f.readlines()
        self.assertEqual(len(lines), 1)
        f.close()
 
        self.p.stop()
        time.sleep(1)
        self.p.start("conf/nginx_multi_token_key_version.conf")
        time.sleep(1)
        os.system("echo '' > logs/error.log")
        os.system("./test_client -T 0 -a '%s' -p 2445 -t 2 2>&1 >/dev/null"%self.ip_list[0])
        f = os.popen("cat logs/error.log | grep 'check_token fail'")
        lines = f.readlines()
        self.assertEqual(len(lines), 0)
        f.close()

        self.p.stop()
        time.sleep(1)
        self.p.start("conf/nginx_one_token_key_version.conf")
        time.sleep(1)
        os.system("echo '' > logs/error.log")
        os.system("./test_client -T 0 -a '%s' -p 2445 -t 2 2>&1 >/dev/null"%self.ip_list[0])
        f = os.popen("cat logs/error.log | grep 'check_token fail'")
 
        lines = f.readlines()
        self.assertEqual(len(lines), 1) # version 0 token has not expired
        f.close()

        print("%s success"%(sys._getframe().f_code.co_name))


    

if __name__ == '__main__':
    unittest.main()
