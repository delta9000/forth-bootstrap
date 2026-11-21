#!/usr/bin/env python3
"""hmp.py SOCK CMD...: send HMP commands to a QEMU monitor socket, print replies."""
import socket, sys, time
s = socket.socket(socket.AF_UNIX)
s.connect(sys.argv[1])
s.settimeout(1.0)
def drain():
    data = b""
    try:
        while True:
            c = s.recv(65536)
            if not c: break
            data += c
    except socket.timeout:
        pass
    return data.decode("latin-1")
drain()
for cmd in sys.argv[2:]:
    s.sendall((cmd + "\n").encode())
    time.sleep(0.3)
    print(f"--- {cmd} @ {time.strftime('%H:%M:%S')}")
    print(drain().replace("\r", ""))
