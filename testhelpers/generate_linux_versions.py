#! /usr/bin/python

import sys
import random

try:
	max_len = int(sys.argv[1])
except:
	max_len = 0

versions = sys.argv[2:]

if max_len <= 0:
	max_len = len(versions)

max_len = min(len(versions), max_len)

if max_len < len(versions):
	random.shuffle(versions)

print("\n".join(sorted(versions[:max_len])))
