#! /usr/bin/python3
# -*- coding: utf-8 -*-


import sys

tabsize = 8


def usage():
    app = 'bracket_align'

    if len(sys.argv) > 0:
        app = sys.argv[0]

    print('%s source.c' % (app))
    sys.exit(1)


def tabs2spaces(line):
    tabpos = line.find('\t')
    while tabpos != -1:
        num_spaces = tabsize - (tabpos % tabsize)
        spaces = ' ' * num_spaces
        line = line[:tabpos] + spaces + line[(tabpos + 1):]
        tabpos = line.find('\t')

    return line


def min_findpos(x, y):
    if x == -1:
        return y
    elif y == -1:
        return x
    else:
        return min(x, y)


def get_first_nonspace(line):
    for i, c in enumerate(line):
        if c != ' ':
            return i

    return -1


def strip_comments_body(line, pos):
    # remove everything from the start pos
    endpos = line.find("*/")
    if endpos == -1:
        in_comment = 1
        endpos = len(line) - 1
    else:
        in_comment = 0

    spaces = ' ' * (endpos - pos + 2)
    line = line[:pos] + spaces + line[(endpos + 2):]

    return (line, in_comment)


def strip_comments(line, in_comment):
    if in_comment == 1:
        (line, in_comment) = strip_comments_body(line, 0)

    if in_comment == 1:
        return (line, in_comment)

    # find new comment
    pos = line.find('/*')
    while pos != -1:
        line = line[:pos] + '  ' + line[(pos + 2):]
        (line, in_comment) = strip_comments_body(line, pos)

        if in_comment == 1:
            return (line, in_comment)
        else:
            pos = line.find('/*')

    return (line, in_comment)


def check_combound_statement(line, pos):
    # check what we expect for combound statement
    if line[pos] == '(':
        expected = '{'
        expected_post = pos + 1
    elif line[pos] == ')':
        expected = '}'
        expected_post = pos - 1
    else:
        return False

    # check if this position is actually possible
    if expected_post < 0 or expected_post > len(line):
        return False

    if line[expected_post] == expected:
        return True
    else:
        False


def main():
    bracket_stack = []

    if len(sys.argv) != 2:
        usage()

    lines = open(sys.argv[1]).readlines()

    # convert tabs to spaces
    lines = list(map(lambda line: tabs2spaces(line).strip('\n\r'), lines))

    # strip comments
    in_comment = 0
    for i, line in enumerate(lines):
        (lines[i], in_comment) = strip_comments(line, in_comment)

    for i, line in enumerate(lines):
        # check for correct alignment
        nonspace_pos = get_first_nonspace(line)
        if nonspace_pos != -1 and len(bracket_stack) != 0:
            expected = bracket_stack[len(bracket_stack) - 1] + 1
            if expected != nonspace_pos:
                print("Found wrong alignment at %s:%u,"
                      " was %u but expected %u" %
                      (sys.argv[1], i + 1, nonspace_pos + 1, expected + 1))

        # create stack of opened and closed brackets
        pos = 0

        pos_open = line.find('(', pos)
        pos_close = line.find(')', pos)
        pos = min_findpos(pos_open, pos_close)
        while pos != -1:
            if not check_combound_statement(line, pos):
                if line[pos] == '(':
                    bracket_stack.append(pos)
                else:
                    bracket_stack.pop()

            pos += 1
            pos_open = line.find('(', pos)
            pos_close = line.find(')', pos)
            pos = min_findpos(pos_open, pos_close)


if __name__ == '__main__':
    main()
