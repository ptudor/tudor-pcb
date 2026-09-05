#!/usr/bin/env python3
"""Run an already compiled ParserProbe in bounded, isolated subprocesses."""
import argparse
import subprocess
import time
import resource

parser = argparse.ArgumentParser()
parser.add_argument('probe')
args = parser.parse_args()
cases = {
    'empty ADD': '%ADD10*%',
    'negative macro count': '%AMbad*4,1,-1,0,0,0,0*%',
    'infinity': '%ADD10P,1Xinf*%',
    'NaN': '%ADD10P,1Xnan*%',
    'billion repeats': '%FSLAX24Y24*%%ADD10C,1*%%SRX1000000000Y1I1J0*%',
    'enormous arc': '%FSLAX24Y24*%%ADD10C,1*%D10*X0Y0D02*G03X1Y0I1000000000J0D01*',
    'large polygon count': '%ADD10P,1X99999999999999999999999*%',
}
def child_limits():
    resource.setrlimit(resource.RLIMIT_CPU, (2, 2))
    # macOS rejects RLIMIT_DATA changes; assert measured peak RSS below instead.

for name, source in cases.items():
    started = time.monotonic()
    result = subprocess.run([args.probe], input=(source + 'D10*X0Y0D03*M02*').encode(),
                            stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=5, preexec_fn=child_limits)
    assert result.returncode == 0, (name, result.returncode, result.stderr.decode(errors='replace'))
    assert result.stdout.startswith(b'REJECTED '), (name, result.stdout)
    print(f'{name}: rejected without crash in {time.monotonic() - started:.3f}s')

peak = resource.getrusage(resource.RUSAGE_CHILDREN).ru_maxrss
assert peak < 256 * 1024 * 1024, peak
print(f"Peak child RSS: {peak} bytes (macOS)")
