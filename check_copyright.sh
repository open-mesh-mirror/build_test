#! /bin/bash

curyear="$(date +'%Y')"
find . -type f -print0| while read -d $'\0' file; do
	grep Copyright "$file" > /dev/null 2>&1
	if [ "$?" != "0" ]; then
		continue
	fi

	year="$(grep -h Copyright "$file"|sed 's/^.*Copyright (C) \([0-9]*-\)*\([0-9]*\)\s\s*B\.A\.T\.M\.A\.N\..*$/\2/')"
	if [ "$year" != "$curyear" ]; then
		echo "$file: $year"
	fi
done
