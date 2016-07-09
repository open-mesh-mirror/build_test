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
	print >> sys.stderr, '\tadd NAME LOGFILE LONGLOGFILE'
	print >> sys.stderr, '\tsend FROM TO TOPIC'
	print >> sys.stderr, '\tadd_buildtests BRANCH VERSION CONFIG'
	sys.exit(1)


def create():
	dbfile = sys.argv[1];
	if os.path.exists(dbfile):
		os.unlink(dbfile)

	con = sqlite3.connect(dbfile)
	cur = con.cursor()
	cur.execute('CREATE TABLE logs (name, log, longlog)')
	cur.execute('CREATE TABLE buildtests (branch, version, config)')
	cur.execute('CREATE UNIQUE INDEX buildtests_unique ON buildtests(branch, version, config)')
	con.commit()
	cur.close()

def add():
	dbfile = sys.argv[1];
	name = sys.argv[3]
	logfile = sys.argv[4]
	longlogfile = sys.argv[5]

	log = open(logfile).read()
	longlog = open(longlogfile).read()

	con = sqlite3.connect(dbfile)
	cur = con.cursor()
	cur.execute('INSERT INTO logs VALUES (?, ?, ?)', (name, log, longlog))
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

def send():
	dbfile = sys.argv[1];
	mail_from = sys.argv[3]
	mail_to = sys.argv[4]
	mail_subject = sys.argv[5]

	con = sqlite3.connect(dbfile)
	cur = con.cursor()
	cur.execute('SELECT name FROM logs ORDER BY name')
	names = cur.fetchall()
	cur.execute('SELECT name,log FROM logs GROUP BY log ORDER BY name')
	logs = cur.fetchall()
	cur.execute('SELECT COUNT(*) FROM buildtests')
	buildcount = cur.fetchall()[0][0]
	cur.close()

	if len(names) == 0:
		return

	name_list = []
	for x in names:
		name_list.append(" * " + x[0])

	log_list = []
	for x in logs:
		namelen = len(x[0])
		if namelen > 75:
			namelen = 75

		underline = '-' * namelen

		full_log = re.sub('^', '    ', x[1], count = 0, flags = re.MULTILINE)
		full_log = re.sub('\s*$', '', full_log, count = 0)

		log_list.append("%s\n%s\n\n%s" % (x[0], underline, full_log))

	mail = []
	mail.append("Name of failed tests\n")
	mail.append("====================\n")
	mail.append("\n")
	mail.append("%s\n" % ("\n".join(name_list)))
	mail.append("\n")
	mail.append("Output of different failed tests\n")
	mail.append("================================\n")
	mail.append("\n")
	mail.append("%s\n" % ("\n\n\n".join(log_list)))
	mail.append("\n")
	mail.append("Statistics\n")
	mail.append("==========\n")
	mail.append("\n")
	mail.append("Failed tests:          %8u\n" % (len(name_list)))
	mail.append("Started build tests:   %8u\n" % (buildcount))

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
	elif sys.argv[2] == 'add' and len(sys.argv) == 6:
		add()
	elif sys.argv[2] == 'add_buildtests' and len(sys.argv) == 6:
		add_buildtests()
	elif sys.argv[2] == 'send' and len(sys.argv) == 6:
		send()
	else:
		usage(prog)

if __name__ == '__main__':
	main()
