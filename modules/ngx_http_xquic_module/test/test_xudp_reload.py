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
import paramiko
import logging

def get_local_ip():
    ip_list = []
    p = os.popen("""ifconfig | grep inet |grep -v inet6 | awk -F " " '{print $2}'""")

    lines = p.readlines()
    for line in lines:
        if ":" not in line:
            ip_list.append(line.strip())

    #ip_list.remove("127.0.0.1")
    if "127.0.0.1" in ip_list:
        ip_list.remove("127.0.0.1")
        ip_list.append("127.0.0.1")
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

    if len(ip_list) == 0:
        ip_list.append("")

    return ip_list


def ssh_remote(remote_ip, username, pk_file):
    try:
        ssh = paramiko.SSHClient()
        ssh.set_missing_host_key_policy(paramiko.AutoAddPolicy())
        pkey = paramiko.RSAKey.from_private_key_file(pk_file)
        ssh.connect(hostname=remote_ip, port=22, username=username, pkey=pkey)
        return ssh
    except Exception as e:
        print("error ssh remote")
        logger = logging.getLogger(__name__)
        logger.exception(e)

    return ""


class TestXudpReload(unittest.TestCase):
    p = nginx.Nginx(config.TENGINE)
    uri = "/h5/"
    host = "acs.waptest.taobao.com"
    tcp_port = 2080
    udp_port = 2081
    local_ip_list = get_local_ip()
    if (len(local_ip_list) >= 1):
        local_ip = local_ip_list[0]
    else:
        local_ip = ""
    local_ipv6_list = get_local_ipv6()
    if (len(local_ipv6_list) >= 1):
        local_ipv6 = local_ipv6_list[0]
    else:
        local_ipv6 = ""
    #print(local_ip_list,local_ipv6_list)
    remote_ip = "11.158.195.58"
    pk_file = "/root/.ssh/test_id_rsa"
    remote_ipv6 = "11.161.48.202"
    ssh = ssh_remote(remote_ip, "root", pk_file)
    ssh6 = ssh_remote(remote_ipv6, "root", pk_file)
    @classmethod
    def setUpClass(self):
        if (self.ssh == "" or self.local_ip == ""):
            print("init ssh error")
            sys.exit(1)
        os.system("cp -f ../../../libs/libxquic/build/tests/test_client ./test_client")
        os.system("chmod +x test_client")
        self.p.start("conf/nginx_xudp_reload.conf")
        os.system("scp -i %s test_client root@%s:/root/"%(self.pk_file, self.remote_ip))
        os.system("scp -i %s test_client root@%s:/root/"%(self.pk_file, self.remote_ipv6))
        time.sleep(4)

    @classmethod
    def tearDownClass(self):
        os.system("rm -f clog")
        self.p.stop()

    def stop_nginx(self):
        self.p.stop()
        time.sleep(2)

    def reload_nginx(self):
        self.p.reload()
        time.sleep(1)

    def clear_error_log(self):
        os.system("rm -f logs/error.log")

    def get_nginx_pid(self):
        cmd = "ps axu | grep nginx | grep worker | grep -v grep | awk -F ' ' '{print $2}'"
        res = subprocess.Popen(cmd,shell=True,stdout=subprocess.PIPE,stderr=subprocess.PIPE)
        stdout,stderr = res.communicate()

        pids = stdout.splitlines()
        pid_list = []
        for pid in pids:
            pid_list.append(pid.decode())
        return pid_list

    def restart_nginx(self):
        self.p.stop()
        time.sleep(3)
        self.p.start("conf/nginx_xudp_reload.conf")
        time.sleep(5)

    def get_pid_from_lines(self, lines):
        pid_dict = {}
        count = 0
        for line in lines:
            if isinstance(line,bytes):
                line = line.decode()
            if "current-pid" in line:
                pid = line.split("=")[1].strip()
                if pid in list(pid_dict.keys()):
                    pid_dict[pid] += 1
                else:
                    pid_dict[pid] = 1
                count += 1
        return (count, pid_dict)

    def check_xudp_status(self):
        cmd = "sudo ip addr | grep xdp"
        res = subprocess.Popen(cmd,shell=True,stdout=subprocess.PIPE,stderr=subprocess.PIPE)
        stdout,stderr = res.communicate()
        stdout = stdout.decode()
        if " xdp " in stdout:
            return True
        return False


    def get_output_when_reload(self, cmd):
        res = subprocess.Popen(cmd,shell=True,stdout=subprocess.PIPE,stderr=subprocess.PIPE)
        time.sleep(1)
        self.reload_nginx()
        try:
            stdout, stderr = res.communicate(timeout=90)
            lines = stdout.splitlines()
            return lines
        except:
            print("subprocess timeout")
            return ""

    def get_ssh_output_when_reload(self, ssh, cmd):
        _, stdout, stderr = ssh.exec_command(cmd, get_pty=True, timeout=10)
        total_result = ""
        recv_count = 0
        err_count = 0
        while True:
            try:
                v = stdout.channel.recv(4096)
            except:
                break
            if not v:
                break
            v = v.decode()
            if "xqc_h3_request_create error" in v:
                #print(v)
                err_count += 1
            if err_count >= 3:
                break
            if "current-pid" in v:
                recv_count += 1
            total_result +=v
            if (recv_count == 3):
                recv_count += 1
                self.reload_nginx()
        #print(total_result)
        lines = total_result.splitlines()
        return lines
    def test_1_xudp_load_balance(self):
        check_xudp = self.check_xudp_status()
        self.assertEqual(check_xudp, True)
        cmd = "./test_client  -a '%s' -p 2081 -D 1 -b 20 -B 200 -t 5 -u 'https://acs.waptest.taobao.com/h5/' "%(self.local_ip)
        #res = subprocess.Popen(cmd,shell=True,stdout=subprocess.PIPE,stderr=subprocess.PIPE)
        #stdout, stderr = res.communicate()

        _, stdout, stderr = self.ssh.exec_command(cmd, get_pty=True, timeout=60)
        total_result = ""
        while True:
            v = stdout.channel.recv(4096)
            if not v:
                break
            v = v.decode()
            total_result +=v
        lines = total_result.splitlines()
        (count, pid_dict) = self.get_pid_from_lines(lines)
        print(count, pid_dict)


        self.assertGreaterEqual(count, 199)
        self.assertLessEqual(count, 203)

        for pk in list(pid_dict.keys()):
            self.assertGreaterEqual(pid_dict[pk], 30)
            self.assertLessEqual(pid_dict[pk], 70)
        print("%s success"%(sys._getframe().f_code.co_name))
    def test_2_xudp_reload(self):
        self.ssh.exec_command("> clog")
        check_xudp = self.check_xudp_status()
        self.assertEqual(check_xudp, True)
        pids = self.get_nginx_pid()

        #print(pids)
        cmd = "./test_client  -a '%s' -p 2081 -D 1 -b 1 -B 1 -t 60 -P 50 -S 1 -u 'https://acs.waptest.taobao.com/h5/' "%(self.local_ip)
        lines = self.get_ssh_output_when_reload(self.ssh, cmd)
        (count, pid_dict) = self.get_pid_from_lines(lines)
        self.assertGreaterEqual(count, 49)
        self.assertLessEqual(count, 52)
        self.assertEqual(len(pid_dict.keys()), 1)
        self.assertIn(list(pid_dict.keys())[0], pids)
        check_xudp = self.check_xudp_status()
        self.assertEqual(check_xudp, True)

        print("%s success"%(sys._getframe().f_code.co_name))
    def test_3_xudp_multipath_reload(self):
        self.ssh.exec_command("> clog")
        # primary path migration
        self.restart_nginx()

        pids = self.get_nginx_pid()
        #print(pids)
        cmd = " ./test_client -a '%s' -p 2445 -s 1024000 -l d -t 3 -M -i eth0 -i eth0 -x 103 -n 100 -E -u 'https://acs.waptest.taobao.com/h5/' "%(self.local_ip)
        #print(cmd)
        lines = self.get_ssh_output_when_reload(self.ssh, cmd)
        (count, pid_dict) = self.get_pid_from_lines(lines)
        check_xudp = self.check_xudp_status()
        self.assertEqual(check_xudp, True)
        #print(count, pid_dict)
        self.assertLessEqual(count,101)
        self.assertGreaterEqual(count,99)
        self.assertEqual(len(pid_dict.keys()), 1)
        self.assertIn(list(pid_dict.keys())[0], pids)

        # secondary path network migration
        self.restart_nginx()
        pids = self.get_nginx_pid()
        cmd = "./test_client -a '%s' -p 2445 -s 1024000 -l d -t 3 -M -i eth0 -i eth0 -x 104 -n 100 -E -u 'https://acs.waptest.taobao.com/h5/' "%(self.local_ip)
        lines = self.get_ssh_output_when_reload(self.ssh, cmd)
        (count, pid_dict) = self.get_pid_from_lines(lines)
        self.assertLessEqual(count,101)
        self.assertGreaterEqual(count,99)
        self.assertEqual(len(pid_dict.keys()), 1)
        self.assertIn(list(pid_dict.keys())[0], pids)
        check_xudp = self.check_xudp_status()
        self.assertEqual(check_xudp, True)

        # primary path closed
        cmd = "./test_client -a '%s' -p 2445 -s 1024000 -l d -t 3 -M -i eth0 -i eth0 -x 105 -n 100 -E -u 'https://acs.waptest.taobao.com/h5/' "%(self.local_ip)
        self.restart_nginx()
        pids = self.get_nginx_pid()
        lines = self.get_ssh_output_when_reload(self.ssh, cmd)
        (count, pid_dict) = self.get_pid_from_lines(lines)
        #self.assertEqual(count, 100)
        self.assertLessEqual(count,101)
        self.assertGreaterEqual(count,99)
        self.assertEqual(len(pid_dict.keys()), 1)
        self.assertIn(list(pid_dict.keys())[0], pids)
        check_xudp = self.check_xudp_status()
        self.assertEqual(check_xudp, True)


        # secondary path closed
        cmd = "./test_client -a '%s' -p 2445 -s 1024000 -l d -t 3 -M -i eth0 -i eth0 -x 106 -n 100 -E -u 'https://acs.waptest.taobao.com/h5/' "%(self.local_ip)
        self.restart_nginx()
        pids = self.get_nginx_pid()
        lines = self.get_ssh_output_when_reload(self.ssh, cmd)
        (count, pid_dict) = self.get_pid_from_lines(lines)
        #self.assertEqual(count, 100)
        self.assertLessEqual(count,101)
        self.assertGreaterEqual(count,99)
        self.assertEqual(len(pid_dict.keys()), 1)
        self.assertIn(list(pid_dict.keys())[0], pids)
        check_xudp = self.check_xudp_status()
        self.assertEqual(check_xudp, True)

        print("%s success"%(sys._getframe().f_code.co_name))

    def test_4_xudp_reload_worker_diff(self):
        self.restart_nginx()
        self.ssh.exec_command("> clog")
        org_worker = "worker_processes 4;"
        modify_worker = "worker_processes 8;"

        # test scenario where worker count after reload is greater than before
        cmd = "sed -i 's/%s/%s/' conf/nginx_xudp_reload.conf"%(org_worker, modify_worker)
        os.system(cmd)
        pids = self.get_nginx_pid()

        cmd = "./test_client  -a '%s' -p 2081 -D 1 -b 1 -B 1 -t 60 -P 50 -S 1 -u 'https://acs.waptest.taobao.com/h5/' "%(self.local_ip)
        print(cmd)
        lines = self.get_ssh_output_when_reload(self.ssh, cmd)
        (count, pid_dict) = self.get_pid_from_lines(lines)
        print(count, pid_dict)
        self.assertLessEqual(count, 40)
        self.assertEqual(len(pid_dict.keys()), 1)
        self.assertIn(list(pid_dict.keys())[0], pids)
        check_xudp = self.check_xudp_status()
        self.assertEqual(check_xudp, True)

        time.sleep(30)
        cmd = "sed -i 's/%s/%s/' conf/nginx_xudp_reload.conf"%(modify_worker, org_worker)
        os.system(cmd)

        #cmd = "./test_client  -a '127.0.0.1' -p 2081 -D 1 -b 1 -B 1 -t 60 -P 50 -S 1 -u 'https://acs.waptest.taobao.com/h5/' "
        cmd = "./test_client  -a '%s' -p 2081 -D 1 -b 20 -B 100 -t 3 -u 'https://acs.waptest.taobao.com/h5/' "%(self.local_ip)
        print(cmd)
        lines = self.get_ssh_output_when_reload(self.ssh, cmd)
        (count, pid_dict) = self.get_pid_from_lines(lines)
        self.assertGreaterEqual(count, 99)
        self.assertLessEqual(count, 103)

        pids = self.get_nginx_pid()
        #print(pid_dict)
        #print(pids)

        check_xudp = self.check_xudp_status()
        self.assertEqual(check_xudp, True)


        print("%s success"%(sys._getframe().f_code.co_name))

    def test_5_xudp_ipv6_load_balance(self):
        self.restart_nginx()
        if self.local_ipv6 == "":
            print("local_ipv6 is null")
            print("%s success"%(sys._getframe().f_code.co_name))
            return

        check_xudp = self.check_xudp_status()
        self.assertEqual(check_xudp, True)
        cmd = "./test_client -6  -a '%s' -p 2081 -D 1 -b 20 -B 200 -t 3 -u 'https://acs.waptest.taobao.com/h5/' "%(self.local_ipv6)
        print(cmd)
        _, stdout, stderr = self.ssh6.exec_command(cmd, get_pty=True, timeout=60)

        total_result = ""
        while True:
            v = stdout.channel.recv(4096)
            if not v:
                break
            v = v.decode()
            total_result +=v
        lines = total_result.splitlines()
        (count, pid_dict) = self.get_pid_from_lines(lines)
        #print(count, pid_dict)


        self.assertGreaterEqual(count, 200)
        self.assertLessEqual(count, 203)

        for pk in list(pid_dict.keys()):
            self.assertGreaterEqual(pid_dict[pk], 30)
            self.assertLessEqual(pid_dict[pk], 70)
        print("%s success"%(sys._getframe().f_code.co_name))

    def test_6_xudp_ipv6_reload(self):
        self.restart_nginx()
        if self.local_ipv6 == "":
            print("local_ipv6 is null")
            print("%s success"%(sys._getframe().f_code.co_name))
            return

        self.ssh6.exec_command("> clog")
        check_xudp = self.check_xudp_status()
        self.assertEqual(check_xudp, True)
        pids = self.get_nginx_pid()

        #print(pids)
        cmd = "./test_client -6  -a '%s' -p 2081 -D 1 -b 1 -B 1 -t 60 -P 50 -S 1 -u 'https://acs.waptest.taobao.com/h5/' "%(self.local_ipv6)
        print(cmd)
        lines = self.get_ssh_output_when_reload(self.ssh6, cmd)
        (count, pid_dict) = self.get_pid_from_lines(lines)
        self.assertGreaterEqual(count, 49)
        self.assertLessEqual(count, 52)
        self.assertEqual(len(pid_dict.keys()), 1)
        self.assertIn(list(pid_dict.keys())[0], pids)
        check_xudp = self.check_xudp_status()
        self.assertEqual(check_xudp, True)

        print("%s success"%(sys._getframe().f_code.co_name))



if __name__ == '__main__':
    unittest.main()
