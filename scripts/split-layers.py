#!/usr/bin/env python3
"""Plan how a folder is split into N image layers of roughly equal size.

Used at the end of the Dockerfile's build stage on /opt/python (the Python
install with PyTorch and every WebUI package, about 3.8 GB compressed). One
layer that large kept getting cut off mid-download on slow or unstable
connections; ten smaller layers download in parallel and retry cheaply.

Usage: split-layers.py ROOT N
Prints "bucket<TAB>path" records, NUL-terminated, to stdout. The Dockerfile
moves each path into /opt/split/<bucket>/<same path> and copies every
bucket as its own layer, so the pieces unpack into the original folder.

How pieces are chosen:
  - Start with ROOT. Any folder larger than (total / N) is replaced by its
    entries, repeatedly, so large packages (torch, the nvidia libraries) are
    broken up while small ones stay whole. Single files are never split.
  - Pieces are placed largest first into the bucket with the least data so
    far; ties go to the lower path name and lower bucket number.
Same contents in, same buckets out, so unchanged packages keep producing
the same layers from build to build.
"""

import os
import sys


def tree_size(path):
    """Bytes under path (symlinks count as their own small size)."""
    st = os.lstat(path)
    if not os.path.isdir(path) or os.path.islink(path):
        return st.st_size
    total = 0
    for dirpath, dirnames, filenames in os.walk(path):
        for name in filenames + [d for d in dirnames if os.path.islink(os.path.join(dirpath, d))]:
            total += os.lstat(os.path.join(dirpath, name)).st_size
    return total


def pieces(root, target):
    """Split root into pieces no larger than target where possible."""
    out = []
    todo = [root]
    while todo:
        path = todo.pop()
        size = tree_size(path)
        is_real_dir = os.path.isdir(path) and not os.path.islink(path)
        if is_real_dir and (path == root or size > target):
            entries = sorted(os.listdir(path))
            if entries:
                todo.extend(os.path.join(path, e) for e in entries)
                continue
        if path != root:
            out.append((size, path))
    return out


def plan(root, n):
    total = tree_size(root)
    target = max(total // n, 1)
    buckets = [0] * n
    result = []
    for size, path in sorted(pieces(root, target), key=lambda p: (-p[0], p[1])):
        i = min(range(n), key=lambda b: (buckets[b], b))
        buckets[i] += size
        result.append((i, path))
    return result, buckets, total


def main():
    root, n = os.path.abspath(sys.argv[1]), int(sys.argv[2])
    result, buckets, total = plan(root, n)
    for i, path in sorted(result, key=lambda r: (r[0], r[1])):
        sys.stdout.write(f"{i}\t{path}\0")
    summary = ", ".join(f"{b / 1e6:.0f}" for b in buckets)
    print(f"split-layers: {total / 1e9:.2f} GB in {len(result)} pieces -> {n} layers (MB): {summary}",
          file=sys.stderr)


if __name__ == "__main__":
    main()
