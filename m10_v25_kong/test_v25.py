#!/usr/bin/env python3
"""DNAOS v25 测: 串口发 h, 看 help 响应"""
import socket, time, sys, os

SOCK = "/tmp/qm25.sock"
LOG = "/tmp/sv25.log"

# 清空 log
open(LOG, 'w').close()

# 起 QEMU (跟 v23 一样参数)
import subprocess
q = subprocess.Popen([
    "qemu-system-i386",
    "-fda", "/tmp/dnaos_v25.img",
    "-serial", "file:" + LOG,
    "-monitor", "unix:" + SOCK + ",server,nowait",
    "-nographic",
    "-no-reboot",
    "-display", "none",
    "-machine", "pc",
    "-m", "32"
], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)

time.sleep(1)

# 连 monitor
s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
s.connect(SOCK)
s.settimeout(2)

def cmd(c):
    s.send((c + "\n").encode())
    time.sleep(0.2)
    try:
        return s.recv(4096).decode()
    except socket.timeout:
        return ""

# 测 1: 'h' 命令 (test help)
print("--- sendkey h ---")
print(cmd("sendkey h"))
time.sleep(0.5)

# 测 2: 'a' (普通字符, 测 echo)
print("--- sendkey a ---")
print(cmd("sendkey a"))
time.sleep(0.3)

# 测 3: 'b' (普通字符)
print("--- sendkey b ---")
print(cmd("sendkey b"))
time.sleep(0.3)

# 测 4: 'x' (随便)
print("--- sendkey x ---")
print(cmd("sendkey x"))
time.sleep(0.3)

# 测 5: ret (Enter)
print("--- sendkey ret ---")
print(cmd("sendkey ret"))
time.sleep(0.3)

# 关
cmd("quit")
s.close()
q.wait(timeout=3)

# 读 log
log = open(LOG, 'rb').read()
print("--- log (raw bytes) ---")
print(repr(log))
print("--- log (decoded) ---")
try:
    print(log.decode('ascii', errors='replace'))
except Exception as e:
    print("decode err:", e)
