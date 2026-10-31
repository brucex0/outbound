#!/usr/bin/env python3
"""Forward Git's SSH traffic with paced input writes; see docs/git-transport.md."""

import os
import select
import subprocess
import sys
import time


def main():
    # Leave SSH authentication, host verification, encryption, and output intact.
    # Small, spaced writes worked around reproducible upload corruption on Bruce's
    # Mac where normal SSH and HTTPS uploads failed integrity checks.
    child = subprocess.Popen(["/usr/bin/ssh", *sys.argv[1:]], stdin=subprocess.PIPE, bufsize=0)
    try:
        while child.poll() is None:
            # A remote rejection must still exit when Git keeps its input open.
            if not select.select([sys.stdin.fileno()], [], [], 0.1)[0]:
                continue
            data = os.read(sys.stdin.fileno(), 4096)
            if not data:
                break
            remaining = memoryview(data)
            while remaining:
                written = child.stdin.write(remaining)
                remaining = remaining[written:]
            time.sleep(0.01)
    except BrokenPipeError:
        # SSH may reject a request before Git finishes sending its pack.
        pass
    except OSError as error:
        print(f"git-ssh-paced: forwarding SSH input failed (errno={error.errno})", file=sys.stderr)
        child.terminate()
        child.wait()
        return 1
    finally:
        child.stdin.close()
    result = child.wait()
    return result if result >= 0 else 128 - result


if __name__ == "__main__":
    sys.exit(main())
