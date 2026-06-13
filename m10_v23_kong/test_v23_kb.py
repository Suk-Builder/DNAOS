#!/usr/bin/env python3
import socket, time, os, sys

SOCK = '/tmp/qm23k.sock'
LOG  = '/tmp/sv23k.log'
IMG  = '/home/ubuntu/dnaos/dnaos_v23.img'

# 清理
for f in [SOCK, LOG]:
    try: os.unlink(f)
    except: pass

# 启 QEMU
import subprocess
q = subprocess.Popen(
    ['qemu-system-i386', '-drive', f'format=raw,file={IMG}',
     '-serial', f'file:{LOG}', '-monitor', f'unix:{SOCK},server,nowait',
     '-display', 'none'])
time.sleep(1)

# 发 sendkey a
s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
s.connect(SOCK)
s.sendall(b'sendkey a\n')
time.sleep(0.3)
s.sendall(b'quit\n')
s.close()
q.wait(timeout=5)

# 输出
print("=== 串口 ===")
os.system(f'xxd {LOG}')
os.system(f'wc -c {LOG}')
