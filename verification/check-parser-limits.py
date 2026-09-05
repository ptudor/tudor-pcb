#!/usr/bin/env python3
"""Run an already compiled ParserProbe in bounded, isolated subprocesses."""
import argparse
import subprocess
import time

parser = argparse.ArgumentParser()
parser.add_argument('probe')
args = parser.parse_args()
cases = {
    'empty ADD': '%ADD10*%',
    'negative macro count': '%AMbad*4,1,-1,0,0,0,0*%',
    'infinity': '%ADD10P,1Xinf*%',
    'NaN': '%ADD10P,1Xnan*%',
    'large polygon count': '%ADD10P,1X99999999999999999999999*%',
}
for name, source in cases.items():
    started = time.monotonic()
    result = subprocess.run([args.probe], input=(source + 'D10*X0Y0D03*M02*').encode(),
                            stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=5)
    assert result.returncode == 0, (name, result.returncode, result.stderr.decode(errors='replace'))
    assert result.stdout.startswith(b'REJECTED '), (name, result.stdout)
    print(f'{name}: rejected without crash in {time.monotonic() - started:.3f}s')
