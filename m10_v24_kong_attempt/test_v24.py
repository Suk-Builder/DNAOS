#!/usr/bin/env python3
import socket, time, os, subprocess

SOCK = '/tmp/qm24.sock'
LOG  = '/tmp/sv24.log'
IMG  = '/home/ubuntu/dnaos/dnaos_v24.img'

for f in [SOCK, LOG]:
    try: os.unlink(f)
    except: pass

q = subprocess.Popen(
    ['qemu-system-i386', '-drive', f'format=raw,file={IMG}',
     '-serial', f'file:{LOG}', '-monitor', f'unix:{SOCK},server,nowait',
     '-display', 'none'],
    stdout=open('/dev/null','w'), stderr=subprocess.STDOUT)
time.sleep(1.5)

s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
s.connect(SOCK)
cmds = ['v','e','r','ret','h','e','l','p','ret','q','u','i','t','ret']
for c in cmds:
    s.sendall(f'sendkey {c}\n'.encode())
    time.sleep(0.15)
s.sendall(b'quit\n')
s.close()
q.wait(timeout=8)

print("=== 串口 ===")
os.system(f'cat {LOG} 2>/dev/null | xxd')
os.system(f'wc -c {LOG} 2>/dev/null')
