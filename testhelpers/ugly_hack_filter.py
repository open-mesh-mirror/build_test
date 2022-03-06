#! /usr/bin/python3
# -*- coding: utf-8 -*-


import sys


def fix_file(f):
    lines = f.readlines()
    t = []
    accept = True

    for l in lines:
        if 'UGLY_HACK' in l:
            if 'UGLY_HACK_NEW' in l:
                accept = True
            elif 'UGLY_HACK_OLD' in l:
                accept = False
            elif 'UGLY_HACK_STOP':
                accept = True

            continue

        if not accept:
            continue

        t.append(l)

    f.seek(0)
    f.truncate()

    f.write(''.join(t))
    


def main():
    for fname in sys.argv[1:]:
        with open(fname, "r+") as f:
            fix_file(f)


if __name__ == '__main__':
    main()
