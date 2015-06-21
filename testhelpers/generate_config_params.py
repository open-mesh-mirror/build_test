#! /usr/bin/python

import sys
import itertools
import random

max_len = 4

configs = sys.argv[1:]
combinations = itertools.product("yn", repeat = len(configs))
pool = tuple(combinations)
random_options = []
for j in range(0, max_len):
	if j >= len(pool):
		break
	
	if len(pool) <= max_len:
		x = pool[j]
	else:
		x = random.choice(pool)

	option_set = []
	for i in range(0, len(configs)):
		option_set.append("CONFIG_BATMAN_ADV_%s=%s" % (configs[i], x[i]))
	options = "+".join(option_set)

	if not options in random_options:
		random_options.append(options)

print("\n".join(random_options))
