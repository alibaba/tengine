#!/usr/bin/env python
# encoding: utf-8

import unittest
import os
import time
import sys
import subprocess
import re

sys.path.append("../../../tests/unittest_pycommon")
import config
import nginx

class TestMaxStreams(unittest.TestCase):
    """测试 xquic_max_streams_bidi 和 xquic_max_streams_uni 配置指令"""
    
    p = nginx.Nginx(config.TENGINE)

    @classmethod
    def setUpClass(self):
        """测试前准备：复制test_client并设置权限"""
        os.system("cp -f ../../../libs/xquic/build/tests/test_client ./test_client")
        os.system("chmod +x test_client")
        print("Test client prepared")

    @classmethod
    def tearDownClass(self):
        """测试后清理：停止nginx"""
        try:
            self.p.stop()
        except:
            pass
        print("Test completed")

    def stop_nginx(self):
        """停止nginx并等待"""
        self.p.stop()
        time.sleep(2)
    
    def test_1_max_streams_custom_values(self):
        print("\n=== 测试用例1: 自定义max_streams配置 ===")
        
        # ========== 第一阶段：测试 -P 20（正常情况） ==========
        print("\n--- 阶段1：测试 -P 20（应该成功） ---")
        
        # 清理日志
        os.system("echo '' > logs/error.log")
        os.system("echo '' > logs/xquic.log")
        os.system("echo '' > clog")
        
        # 启动nginx with自定义max_streams配置
        self.stop_nginx()
        self.p.start("conf/nginx_max_streams.conf")
        time.sleep(2)
        
        # 执行test_client连接测试，P=20表示创建20个并发stream
        cmd = "./test_client -a 127.0.0.1 -p 2081 -u 'https://test.taobao.com/test' -D 1 -b 1 -B 1 -s 10 -P 20 -1 -t 10 2>&1"
        try:
            result = subprocess.run(cmd, shell=True, timeout=15, 
                                   stdout=subprocess.PIPE, stderr=subprocess.PIPE, 
                                   universal_newlines=True)
            print(f"Client output (P=20): {result.stdout[:200]}")
        except subprocess.TimeoutExpired:
            print("Client test timeout (expected)")
        except Exception as e:
            print(f"Client test exception: {e}")
        
        time.sleep(3)
        
        # 读取xquic.log中的xqc_conn_destroy report记录
        f = os.popen("cat logs/xquic.log | grep 'xqc_conn_destroy' | grep 'report'")
        xquic_log = f.read()
        f.close()
        
        print(f"xqc_conn_destroy log (P=20): {xquic_log[:500]}")
        
        # 验证连接建立成功（应该有xqc_conn_destroy记录）
        self.assertGreater(len(xquic_log), 0, 
                          "P=20时应该有xqc_conn_destroy日志输出")
        
        # 使用正则表达式提取passive_bidi_s_max的值
        match = re.search(r'passive_bidi_s_max:(\d+)', xquic_log)
        self.assertIsNotNone(match, "P=20时应该能找到passive_bidi_s_max字段")
        
        passive_bidi_s_max = int(match.group(1))
        print(f"提取到的 passive_bidi_s_max (P=20) = {passive_bidi_s_max}")
        
        # 验证passive_bidi_s_max是否等于20（与-P参数一致）
        self.assertEqual(passive_bidi_s_max, 20,
                        f"P=20时passive_bidi_s_max应该等于20，但实际值为{passive_bidi_s_max}")
        
        print(f"阶段1成功 - passive_bidi_s_max={passive_bidi_s_max}")
        
        # ========== 第二阶段：测试 -P 21（应该超限） ==========
        print("\n--- 阶段2：测试 -P 21（应该触发exceed max_streams_bidi_can_recv错误） ---")
        
        # 清空所有日志
        os.system("echo '' > logs/error.log")
        os.system("echo '' > logs/xquic.log")
        os.system("echo '' > clog")
        
        time.sleep(2)
        
        # 执行test_client连接测试，P=21表示创建21个并发stream（超过限制）
        cmd = "./test_client -a 127.0.0.1 -p 2081 -u 'https://test.taobao.com/test' -D 1 -b 1 -B 1 -s 10 -P 21 -1 -t 10 2>&1"
        
        # 使用Popen而不是run，方便处理可能卡住的情况
        import signal
        process = subprocess.Popen(cmd, shell=True, 
                                   stdout=subprocess.PIPE, 
                                   stderr=subprocess.PIPE,
                                   universal_newlines=True,
                                   preexec_fn=os.setsid)
        
        # 等待15秒，如果还没完成就强制终止
        try:
            stdout, stderr = process.communicate(timeout=15)
            print(f"Client output (P=21): {stdout[:200]}")
        except subprocess.TimeoutExpired:
            print("Client test timeout (P=21), killing process...")
            # 杀死整个进程组
            os.killpg(os.getpgid(process.pid), signal.SIGTERM)
            time.sleep(1)
            # 如果还没死，强制kill
            try:
                os.killpg(os.getpgid(process.pid), signal.SIGKILL)
            except:
                pass
            print("Process killed due to timeout")
        except Exception as e:
            print(f"Client test exception (P=21): {e}")
        
        time.sleep(3)
        
        # 检查error.log中是否存在"exceed max_streams_bidi_can_recv"错误
        f = os.popen("cat logs/error.log | grep 'exceed max_streams_bidi_can_recv'")
        error_log = f.read()
        f.close()
        
        print(f"Error log (P=21): {error_log[:300] if error_log else '未找到exceed错误'}")
        
        # 验证应该存在超限错误
        self.assertGreater(len(error_log.strip()), 0,
                          "P=21时应该在error.log中找到'exceed max_streams_bidi_can_recv'错误")
        
        # 同时检查xquic.log
        f = os.popen("cat logs/xquic.log | grep 'exceed max_streams_bidi_can_recv'")
        xquic_error = f.read()
        f.close()
        
        if xquic_error:
            print(f"xquic.log中也找到exceed错误: {xquic_error[:300]}")
        
        print(f"\n{sys._getframe().f_code.co_name} success - P=20和P=21测试均通过")
    
    def test_2_max_streams_default_values(self):
        """测试用例2: 验证不设置max_streams时使用默认值，然后reload成自定义值"""
        print("\n=== 测试用例2: 默认配置 + reload测试 ===")
        
        # ========== 阶段1：注释掉max_streams配置，测试默认值 ==========
        print("\n--- 阶段1：注释掉max_streams配置，测试默认值 -P 50 ---")
        
        # 注释掉max_streams配置行
        os.system("sed -i 's/^\\s*xquic_max_streams_bidi/#&/' conf/nginx_max_streams.conf")
        os.system("sed -i 's/^\\s*xquic_max_streams_uni/#&/' conf/nginx_max_streams.conf")
        
        # 清理日志
        os.system("echo '' > logs/error.log")
        os.system("echo '' > logs/xquic.log")
        os.system("echo '' > clog")
        
        # 启动nginx
        self.stop_nginx()
        self.p.start("conf/nginx_max_streams.conf")
        time.sleep(2)
        
        # 执行test_client连接测试，P=50表示创建50个并发stream（测试默认值是否足够大）
        cmd = "./test_client -a 127.0.0.1 -p 2081 -u 'https://test.taobao.com/test' -D 1 -b 1 -B 1 -s 10 -P 50 -1 -t 10 2>&1"
        
        # 使用Popen处理可能的超时情况
        import signal
        process = subprocess.Popen(cmd, shell=True,
                                   stdout=subprocess.PIPE,
                                   stderr=subprocess.PIPE,
                                   universal_newlines=True,
                                   preexec_fn=os.setsid)
        
        # 等待15秒
        client_output = ""
        try:
            stdout, stderr = process.communicate(timeout=15)
            client_output = stdout
            print(f"Client output (P=50): {stdout[:200]}")
        except subprocess.TimeoutExpired:
            print("Client test timeout (expected)")
            # 杀死进程组
            os.killpg(os.getpgid(process.pid), signal.SIGTERM)
            time.sleep(1)
            try:
                os.killpg(os.getpgid(process.pid), signal.SIGKILL)
            except:
                pass
            print("Process killed due to timeout")
        except Exception as e:
            print(f"Client test exception: {e}")
        
        time.sleep(3)
        
        # 统计test_client输出中":status = 200"的数量
        status_200_count = client_output.count(":status = 200")
        print(f"在test_client输出中找到 {status_200_count} 个 ':status = 200'")
        
        # 验证应该有50个成功的响应
        self.assertGreaterEqual(status_200_count, 50,
                        f"应该有50个':status = 200'响应，但实际只有{status_200_count}个")
        
        # 检查error.log中不应该存在"exceed max_streams_bidi_can_recv"错误
        f = os.popen("cat logs/error.log | grep 'exceed max_streams_bidi_can_recv'")
        error_log = f.read()
        f.close()
        
        # 验证不应该有超限错误（默认值应该足够大）
        self.assertEqual(len(error_log.strip()), 0,
                        f"P=50时不应该出现'exceed max_streams_bidi_can_recv'错误，但找到了: {error_log[:200]}")
        
        print(f"验证通过：P=50时没有exceed错误")
        
        # 读取xquic.log中的xqc_conn_destroy report记录
        f = os.popen("cat logs/xquic.log | grep 'xqc_conn_destroy' | grep 'report'")
        xquic_log = f.read()
        f.close()
        
        # 验证连接建立成功
        self.assertGreater(len(xquic_log), 0,
                          "应该有xqc_conn_destroy日志输出")
        
        # 尝试提取passive_bidi_s_max的值（用于信息展示）
        match = re.search(r'passive_bidi_s_max:(\d+)', xquic_log)
        if match:
            passive_bidi_s_max = int(match.group(1))
            print(f"提取到的 passive_bidi_s_max (默认配置) = {passive_bidi_s_max}")
            # 验证默认配置下能处理50个stream
            self.assertGreaterEqual(passive_bidi_s_max, 50,
                                   f"默认配置的passive_bidi_s_max应该>=50，但实际值为{passive_bidi_s_max}")
        else:
            print("未找到passive_bidi_s_max字段（可能连接未正常关闭）")
                
        # ========== 阶段2：还原配置，reload测试 -P 20 ==========
        print("\n--- 阶段2：还原max_streams配置，reload测试 -P 20 ---")
                
        # 还原max_streams配置行（去掉注释）
        os.system("sed -i 's/^\\s*#\\(\\s*xquic_max_streams_bidi\\)/\\1/' conf/nginx_max_streams.conf")
        os.system("sed -i 's/^\\s*#\\(\\s*xquic_max_streams_uni\\)/\\1/' conf/nginx_max_streams.conf")
        
        # 清空日志
        os.system("echo '' > logs/error.log")
        os.system("echo '' > logs/xquic.log")
        os.system("echo '' > clog")
                
        # reload配置
        self.p.reload()
        time.sleep(3)  # 等待reload完成
                
        # 执行test_client，P=20（应该成功）
        cmd = "./test_client -a 127.0.0.1 -p 2081 -u 'https://test.taobao.com/test' -D 1 -b 1 -B 1 -s 10 -P 20 -1 -t 10 2>&1"
                
        process = subprocess.Popen(cmd, shell=True,
                                   stdout=subprocess.PIPE,
                                   stderr=subprocess.PIPE,
                                   universal_newlines=True,
                                   preexec_fn=os.setsid)
                
        client_output_reload = ""
        try:
            stdout, stderr = process.communicate(timeout=15)
            client_output_reload = stdout
            print(f"Client output (reload, P=20): {stdout[:200]}")
        except subprocess.TimeoutExpired:
            print("Client test timeout (expected)")
            os.killpg(os.getpgid(process.pid), signal.SIGTERM)
            time.sleep(1)
            try:
                os.killpg(os.getpgid(process.pid), signal.SIGKILL)
            except:
                pass
            print("Process killed due to timeout")
        except Exception as e:
            print(f"Client test exception: {e}")
                
        time.sleep(3)
                
        # 统计状态码2 00的数量（使用更精确的匹配）
        # test_client输出格式：":status = 200"，但可能有多余的空格
        status_200_matches = re.findall(r':status\s*=\s*200', client_output_reload)
        status_200_count_reload = len(status_200_matches)
        print(f"重载后找到 {status_200_count_reload} 个 ':status = 200'")
                
        # 验证应该有20个成功响应（允许一个误差，因为reload期间可能有重试）
        self.assertGreaterEqual(status_200_count_reload, 20,
                        f"重载后应该至少有20个':status = 200'响应，但实际只有{status_200_count_reload}个")
        self.assertLessEqual(status_200_count_reload, 22,
                        f"重载后应该不超过22个':status = 200'响应，但实际有{status_200_count_reload}个")
                
        # 读取xquic.log验证passive_bidi_s_max
        f = os.popen("cat logs/xquic.log | grep 'xqc_conn_destroy' | grep 'report'")
        xquic_log_reload = f.read()
        f.close()
                
        match_reload = re.search(r'passive_bidi_s_max:(\d+)', xquic_log_reload)
        if match_reload:
            passive_bidi_s_max_reload = int(match_reload.group(1))
            print(f"重载后的 passive_bidi_s_max = {passive_bidi_s_max_reload}")
            # 验证重载后配置生效，应该是20
            self.assertEqual(passive_bidi_s_max_reload, 20,
                           f"重载后passive_bidi_s_max应该等于20，但实际值为{passive_bidi_s_max_reload}")
        
        # ========== 阶段3：测试 -P 21（应该超限） ==========
        print("\n--- 阶段3：重载后测试 -P 21（应该触发exceed max_streams_bidi_can_recv错误） ---")
        
        # 清空日志
        os.system("echo '' > logs/error.log")
        os.system("echo '' > logs/xquic.log")
        os.system("echo '' > clog")
        
        time.sleep(2)
        
        # 执行test_client，P=21（应该超限）
        cmd = "./test_client -a 127.0.0.1 -p 2081 -u 'https://test.taobao.com/test' -D 1 -b 1 -B 1 -s 10 -P 21 -1 -t 10 2>&1"
        
        process = subprocess.Popen(cmd, shell=True,
                                   stdout=subprocess.PIPE,
                                   stderr=subprocess.PIPE,
                                   universal_newlines=True,
                                   preexec_fn=os.setsid)
        
        # 等待15秒，如果还没完成就强制终止
        try:
            stdout, stderr = process.communicate(timeout=15)
            print(f"Client output (reload P=21): {stdout[:200]}")
        except subprocess.TimeoutExpired:
            print("Client test timeout (P=21), killing process...")
            # 杀死整个进程组
            os.killpg(os.getpgid(process.pid), signal.SIGTERM)
            time.sleep(1)
            try:
                os.killpg(os.getpgid(process.pid), signal.SIGKILL)
            except:
                pass
            print("Process killed due to timeout")
        except Exception as e:
            print(f"Client test exception (P=21): {e}")
        
        time.sleep(3)
        
        # 检查error.log中是否存在"exceed max_streams_bidi_can_recv"错误
        f = os.popen("cat logs/error.log | grep 'exceed max_streams_bidi_can_recv'")
        error_log_p21 = f.read()
        f.close()
        
        print(f"Error log (reload P=21): {error_log_p21[:300] if error_log_p21 else '未找到exceed错误'}")
        
        # 验证应该存在超限错误（证明重载后的配置生效了）
        self.assertGreater(len(error_log_p21.strip()), 0,
                          "重载后P=21时应该在error.log中找到'exceed max_streams_bidi_can_recv'错误")
        
        print(f"\n{sys._getframe().f_code.co_name} success - P=50、重载P=20和重载P=21测试均通过")



if __name__ == '__main__':
    # 运行测试
    unittest.main(verbosity=2)
