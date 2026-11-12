#!/usr/bin/env python3
"""Builds au.com.kellogs12.dumblg.launcher IPK package."""
import io
import os
import tarfile
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parent
LAUNCHER_DIR = ROOT / 'launcher'
OUTPUT_DIR = ROOT / 'dist'
APP_ID = 'au.com.kellogs12.dumblg.launcher'
VERSION = '0.1.0'
IPK_NAME = f'{APP_ID}_{VERSION}_all.ipk'

def make_ar(members):
    buf = bytearray(b'!<arch>\n')
    for name, data in members:
        header = f'{name:<16}{int(time.time()):<12}0     0     100644  {len(data):<10}`\n'.encode('ascii')
        buf.extend(header)
        buf.extend(data)
        if len(data) % 2 == 1:
            buf.extend(b'\n')
    return bytes(buf)

def build_ipk():
    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)
    out_ipk = OUTPUT_DIR / IPK_NAME

    # 1. debian-binary
    debian_binary = b'2.0\n'

    # 2. control.tar.gz
    control_content = (
        f'Package: {APP_ID}\n'
        f'Version: {VERSION}\n'
        'Section: misc\n'
        'Priority: optional\n'
        'Architecture: all\n'
        'Maintainer: Kellogs12\n'
        'Description: DumbLG Clean Home Launcher for webOS 4.5\n'
    ).encode('utf-8')

    control_buf = io.BytesIO()
    with tarfile.open(fileobj=control_buf, mode='w:gz') as tar:
        ti = tarfile.TarInfo(name='./control')
        ti.size = len(control_content)
        ti.mtime = int(time.time())
        ti.mode = 0o644
        tar.addfile(ti, io.BytesIO(control_content))
    control_tar_gz = control_buf.getvalue()

    # 3. data.tar.gz
    data_buf = io.BytesIO()
    with tarfile.open(fileobj=data_buf, mode='w:gz') as tar:
        app_prefix = f'usr/palm/applications/{APP_ID}'
        for root, dirs, files in os.walk(LAUNCHER_DIR):
            rel_dir = os.path.relpath(root, LAUNCHER_DIR)
            arc_dir = app_prefix if rel_dir == '.' else f'{app_prefix}/{rel_dir}'
            di = tarfile.TarInfo(name=arc_dir)
            di.type = tarfile.DIRTYPE
            di.mode = 0o755
            di.mtime = int(time.time())
            tar.addfile(di)

            for f in files:
                if f.startswith('.'):
                    continue
                file_path = os.path.join(root, f)
                arc_file = f'{arc_dir}/{f}'
                with open(file_path, 'rb') as fp:
                    content = fp.read()
                ti = tarfile.TarInfo(name=arc_file)
                ti.size = len(content)
                ti.mode = 0o755 if f.endswith(('.sh', '.py')) else 0o644
                ti.mtime = int(time.time())
                tar.addfile(ti, io.BytesIO(content))
    data_tar_gz = data_buf.getvalue()

    ipk_bytes = make_ar([
        ('debian-binary', debian_binary),
        ('control.tar.gz', control_tar_gz),
        ('data.tar.gz', data_tar_gz)
    ])

    with open(out_ipk, 'wb') as f:
        f.write(ipk_bytes)

    print(f'Successfully built {out_ipk} ({len(ipk_bytes)} bytes)')
    return out_ipk

if __name__ == '__main__':
    build_ipk()
