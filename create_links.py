#! /usr/bin/python
# -*- coding: utf-8 -*-
# find linux-* -type f -exec sha1sum '{}' \; > checksums

import posixpath
from posixpath import curdir, sep, pardir, join

def relpath(path, start=curdir):
	"""Return a relative version of a path"""
	if not path:
		raise ValueError("no path specified")
	start_list = posixpath.abspath(start).split(sep)
	path_list = posixpath.abspath(path).split(sep)
	# Work out how much of the filepath is shared by start and path.
	i = len(posixpath.commonprefix([start_list, path_list]))
	rel_list = [pardir] * (len(start_list)-i) + path_list[i:]
	if not rel_list:
		return curdir
	return join(*rel_list)


import os, os.path

lines = open("checksums").readlines()

files = {}
for line in lines:
	t = line.split()
	if len(t) != 2:
		print("Error in line "+line)
	if files.get(t[0]) == None:
		files[t[0]] = []
	files[t[0]].append(t[1])

print("%d files and %d contents" % (len(lines), len(files)))

for f in files.items():
	if len(f[1]) > 1:
		for t in f[1][1:]:
			relsource = relpath(f[1][0], os.path.dirname(t))
			os.remove(t)
			os.symlink(relsource, t)
