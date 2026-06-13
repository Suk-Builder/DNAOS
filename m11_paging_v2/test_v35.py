#!/usr/bin/env python3
"""v25 + mbr_v35 测 (with r 键 for FAT12)"""
import socket, time, subprocess

SOCK = "/tmp/qm35.sock"
LOG = "/tmp/sm35.log"

open(LOG, 'w').close()

q = subprocess.Popen([
    "qemu-system-i386",
    "-fda", "/tmp/img_v35.img",
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
s.settimeout(1)

s.send(b"sendkey a\n")
time.sleep(0.3)
s.send(b"sendkey b\n")
time.sleep(0.3)
s.send(b"sendkey r\n")
time.sleep(1.5)

s.send(b"quit\n")
s.close()
try:
    q.wait(timeout=3)
except:
    q.kill()

log = open(LOG, 'rb').read()
print("log bytes:", len(log))
print(repr(log[-300:]))
