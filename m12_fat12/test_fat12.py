#!/usr/bin/env python3
"""DNAOS v12 FAT12 read test"""
import socket, time, subprocess

SOCK = "/tmp/qm12.sock"
LOG = "/tmp/sm12.log"

open(LOG, 'w').close()

q = subprocess.Popen([
    "qemu-system-i386",
    "-fda", "/tmp/img_with_readme.img",
    "-serial", "file:" + LOG,
    "-monitor", "unix:" + SOCK + ",server,nowait",
    "-nographic",
    "-no-reboot",
    "-display", "none",
    "-machine", "pc",
    "-m", "32"
], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)

time.sleep(1)
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

# 测 'r' 命令
print("--- sendkey r ---")
print(cmd("sendkey r"))
time.sleep(0.5)

cmd("quit")
s.close()
try:
    q.wait(timeout=5)
except:
    q.kill()

log = open(LOG, 'rb').read()
print("--- log ---")
print(repr(log[:300]))
