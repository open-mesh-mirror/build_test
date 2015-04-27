#!/usr/bin/python
# -*- coding: UTF-8 -*-

import sqlite3
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
	sys.exit(1)


def create():
	dbfile = sys.argv[1];
	if os.path.exists(dbfile):
		os.unlink(dbfile)

	con = sqlite3.connect(dbfile)
	cur = con.cursor()
	cur.execute('CREATE TABLE logs (name, log, longlog)')
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
	cur.close()
	
	if len(names) == 0:
		return

	name_list = []
	for x in names:
		name_list.append(" * " + x[0])

	log_list = []
	for x in logs:
		log_list.append(":\n>>>>>>>>\n".join(x))

	mail = []
	mail.append("Name of failed tests\n")
	mail.append("====================\n")
	mail.append("\n")
	mail.append("%s\n" % ("\n".join(name_list)))
	mail.append("\n")
	mail.append("Output of different failed tests\n")
	mail.append("================================\n")
	mail.append("\n")
	mail.append("%s\n" % ("\n".join(log_list)))

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
	elif sys.argv[2] == 'send' and len(sys.argv) == 6:
		send()
	else:
		usage(prog)

if __name__ == '__main__':
	main()
