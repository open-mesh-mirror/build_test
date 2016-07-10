#!/usr/bin/python
# -*- coding: UTF-8 -*-

import sqlite3
import re
import sys
import os
import smtplib
from email.mime.text import MIMEText

def usage(prog):
	print >> sys.stderr, '%s FILE COMMAND\n' % (prog)
	print >> sys.stderr, 'COMMAND:'
	print >> sys.stderr, '\tcreate'
	print >> sys.stderr, '\tadd BRANCH NAME LOGFILE LONGLOGFILE'
	print >> sys.stderr, '\tsend FROM TO TOPIC'
	print >> sys.stderr, '\tadd_buildtests BRANCH VERSION CONFIG'
	sys.exit(1)


def create():
	dbfile = sys.argv[1];
	if os.path.exists(dbfile):
		os.unlink(dbfile)

	con = sqlite3.connect(dbfile)
	cur = con.cursor()
	cur.execute('CREATE TABLE logs (branch, name, log, longlog)')
	cur.execute('CREATE TABLE buildtests (branch, version, config)')
	cur.execute('CREATE UNIQUE INDEX buildtests_unique ON buildtests(branch, version, config)')
	con.commit()
	cur.close()

def add():
	dbfile = sys.argv[1];
	branch = sys.argv[3]
	name = sys.argv[4]
	logfile = sys.argv[5]
	longlogfile = sys.argv[6]

	log = open(logfile).read()
	longlog = open(longlogfile).read()

	con = sqlite3.connect(dbfile)
	cur = con.cursor()
	cur.execute('INSERT INTO logs VALUES (?, ?, ?, ?)', (branch, name, log, longlog))
	con.commit()
	cur.close()

def add_buildtests():
	dbfile = sys.argv[1];
	branch = sys.argv[3]
	version = sys.argv[4]
	config = sys.argv[5]

	try:
		con = sqlite3.connect(dbfile)
		cur = con.cursor()
		cur.execute('INSERT INTO buildtests VALUES (?, ?, ?)', (branch, version, config))
		a = con.commit()
		cur.close()
		sys.exit(0)
	except sqlite3.IntegrityError:
		sys.exit(1)

def add_branchescounter_to_set(branchset, counter):
	for c in counter:
		branchset.add(c[0])

def get_branchescounter(branch, counter):
	for c in counter:
		if c[0] == branch:
			return c[1]

	return 0

def send():
	dbfile = sys.argv[1];
	mail_from = sys.argv[3]
	mail_to = sys.argv[4]
	mail_subject = sys.argv[5]
	branches = set()

	con = sqlite3.connect(dbfile)
	cur = con.cursor()
	cur.execute('SELECT branch,name FROM logs ORDER BY name')
	names = cur.fetchall()
	cur.execute('SELECT branch,name,log FROM logs GROUP BY log ORDER BY name')
	logs = cur.fetchall()
	cur.execute('SELECT branch, COUNT(*) FROM logs group by branch')
	failcount = cur.fetchall()
	cur.execute('SELECT branch, COUNT(*) FROM buildtests group by branch')
	buildcount = cur.fetchall()
	cur.execute('SELECT branch, COUNT(DISTINCT version) FROM buildtests group by branch')
	versioncount = cur.fetchall()
	cur.execute('SELECT branch, COUNT(DISTINCT config) FROM buildtests group by branch')
	configcount = cur.fetchall()
	cur.close()

	if len(names) == 0:
		return

	add_branchescounter_to_set(branches, failcount)
	add_branchescounter_to_set(branches, buildcount)
	add_branchescounter_to_set(branches, versioncount)
	add_branchescounter_to_set(branches, configcount)

	log_list = []
	for x in logs:
		name = "%s: %s" % (x[0], x[1])
		namelen = len(name)
		namelen = min(namelen, 75)

		underline = '-' * namelen

		full_log = re.sub('^', '    ', x[2], count = 0, flags = re.MULTILINE)
		full_log = re.sub('\s*$', '', full_log, count = 0)

		log_list.append("%s\n%s\n\n%s" % (name, underline, full_log))

	mail = []
	mail.append("Name of failed tests\n")
	mail.append("====================\n")
	mail.append("\n")

	for b in branches:
		name_list = []
		for x in names:
			if x[0] != b:
				continue

			name_list.append(" * %s" % (x[1]))

		if len(name_list) == 0:
			continue

		name = "%s" % (b)
		namelen = len(name)
		namelen = min(namelen, 75)

		underline = '-' * namelen

		mail.append("%s\n%s\n\n%s\n" % (name, underline, "\n".join(name_list)))
		mail.append("\n")

	mail.append("Output of different failed tests\n")
	mail.append("================================\n")
	mail.append("\n")
	mail.append("%s\n" % ("\n\n\n".join(log_list)))
	mail.append("\n")
	mail.append("Statistics\n")
	mail.append("==========\n")
	mail.append("\n")

	for b in branches:
		namelen = len(b)
		namelen = min(namelen, 75)
		underline = '-' * namelen

		mail.append("\n%s\n%s\n\n" % (b, underline))

		failcnt = get_branchescounter(b, failcount)
		buildcnt = get_branchescounter(b, buildcount)
		versioncnt = get_branchescounter(b, versioncount)
		configcnt = get_branchescounter(b, configcount)
		mail.append("Failed tests:          %8u\n" % (failcnt))
		mail.append("Started build tests:   %8u\n" % (buildcnt))
		mail.append("Tested Linux versions: %8u\n" % (versioncnt))
		mail.append("Tested configs:        %8u\n" % (configcnt))

	mail.append("\n")

	msg = MIMEText("".join(mail))
	msg['Subject'] = mail_subject
	msg['From'] = mail_from
	msg['To'] = mail_to

	f = open("mail", "w")
	f.write(msg.as_string())
	f.close()

	os.system("/usr/sbin/sendmail -t < mail")
	#s = smtplib.SMTP('localhost')
	#s.sendmail(mail_from, [mail_to], msg.as_string())
	#s.quit()

def main():
	prog = 'mail_aggregator.py'
	if len(sys.argv) >= 1:
		prog = sys.argv[0]

	if len(sys.argv) < 3:
		usage(prog)

	if sys.argv[2] == 'create' and len(sys.argv) == 3:
		create()
	elif sys.argv[2] == 'add' and len(sys.argv) == 7:
		add()
	elif sys.argv[2] == 'add_buildtests' and len(sys.argv) == 6:
		add_buildtests()
	elif sys.argv[2] == 'send' and len(sys.argv) == 6:
		send()
	else:
		usage(prog)

if __name__ == '__main__':
	main()
