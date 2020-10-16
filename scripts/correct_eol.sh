#!/bin/bash

# copyright 2020 Edmundo Carmona Antoranz
# Released under the terms of GPLv2

echo correct_eol.sh
echo copyright 2020 Edmundo Carmona Antoranz
echo Released under the terms of GPLv2

function getFormat {
  read -r -d '' script <<-"EOF"
	import sys
  
	data=sys.stdin.buffer.read()
  
	unix=False
	mac=False
	dos=False
	i = 0
	while (i < len(data)):
	  if data[i] == ord('\n'):
	    # it's unix
	    unix = True
	    if mac or dos:
	      break # mixed, no need to continue
	  elif data[i] == ord('\r'):
	    if i+1 < len(data):
	      # need to see what's coming
	      if data[i+1] == ord('\n'):
	        dos = True
	        i+=1 # skip next char
	        if unix or mac:
	          break # mixed, no need to continue
	      else:
	        mac = True
	        if dos or unix:
	          break # mixed, no need to continue
	    else:
	      # it was the last character
	      mac = True
	  i+=1

	if not (dos or mac or unix):
	  print("unknown")
	elif dos:
	  if unix or mac:
	    print("mixed")
	  else:
	    print("dos")
	elif mac:
	  if unix:
	    print("mixed")
	  else:
	    print("mac")
	else:
	  print("unix")

EOF
  git show $1:"$2" | python3 -c "$script"
}

function transform {
	# the only argument will be the output format
  read -r -d '' script <<-"EOF"
	import sys
	
	format=sys.argv[1]
	
	def printLineBreak():
	  if format != "unix":
	    sys.stdout.write("\r")
	  if format != "mac":
	    sys.stdout.write("\n")
  
	data=sys.stdin.buffer.read()
	i = 0
	while (i < len(data)):
	  if data[i] == ord('\n'):
	    # it's unix input and it's a line break
	    printLineBreak()
	  elif data[i] == ord('\r'):
	    printLineBreak()
	    if i+1 < len(data):
	      # need to see what's coming
	      if data[i+1] == ord('\n'):
	        i+=1 # skip next char
	    else:
	      # it was the last character
	      None
	  else:
	    sys.stdout.write(chr(data[i]))
	  i+=1
EOF
  python3 -c "$script" $1
}

which python3 > /dev/null
if [ $? -ne 0 ]; then
	echo Seems like you don\'t have python3 installed. Can\'t continue
	exit 1
fi

which git > /dev/null
if [ $? -ne 0 ]; then
	echo Seems like you don\'t have git installed. Can\'t continue
	exit 1
fi

git status --short &> /dev/null
if [ $? -ne 0 ]; then
	echo
	echo You are not in a git working tree, apparently.
	exit 1
fi

# make sure that the working tree is clean
lines=$( git status --short | grep -v "^\\?" | wc -l )
if [ $lines -ne 0 ]; then
	echo
	echo Your working tree is not clean. Can\'t work on it
	exit 1
fi

# making sure that there are so many parameters
if [ $# -lt 3 ]; then
	echo
	echo Not enough parameters
	exit 1
fi

# making sure the revisions do exist
start_rev=$( git rev-parse "$1" )
if [ $? -ne 0 ]; then
	echo
	echo Starting revision "($1)" appears not to be something present in this repo
	exit 1
fi

end_rev=$( git rev-parse "$2" )
if [ $? -ne 0 ]; then
	echo
	echo Ending revision "($2)" appears not to be something present in this repo
	exit 1
fi

# making sure there are no merges in what is being asked to rewrite
lines=$( git rev-list --merges --pretty=%h ^$start_rev $end_rev | head -n 1 )
if [ "$lines" != "" ]; then
	echo
	echo There are merges between $1 and $2
	exit 1
fi

# should save the EOL format of the files that were asked to be reformatted
# skip first 2 params
shift 2

total_files=$#
files=()
formats=()

while [ $# -gt 0 ]; do
	file="$1"
	format=$( getFormat $start_rev "$file" )
	if [ $? -ne 0 ]; then
		echo There was an error detecting EOL format of $file
		exit 1
	fi
	case $format in
	"unknown")
		echo $file has no line breaks. Can\'t tell its original EOL type. Assuming it is NIX
		format=unix
		;;
	"mixed")
		echo $file uses more than one EOL marker. Quitting.
		exit 1
		;;
	*)
		echo file: $file EOL format: $format
		files+=( "$file" )
		formats+=( $format )
		;;
	esac
	shift
done

echo Checking out starting revision "($( git show --summary --pretty="%h %s" --quiet $start_rev ))"
git checkout $start_rev &> /dev/null
if [ $? -ne 0 ]; then
	echo
	echo Error checking out $1. Aborting
	exit 1
fi

git log --reverse --pretty=%h $start_rev..$end_rev |  while read revision; do
	echo Bringing over revision $revision \($( git show --summary --pretty=%s --quiet $revision )\)
	git cherry-pick $revision &> /dev/null
	cherry_pick_result=$?
	# there is a conflict, means there is a problem with the EOL formats at some file
	for i in $( seq 0 $(( $total_files - 1 )) ); do
		file=${files[$i]}
		format=${formats[$i]}
		git show $revision:"$file" | transform $format > "$file"
		git add "$file"
	done
	# wrap up revision
	if [ $cherry_pick_result -eq 0 ]; then
		GIT_EDITOR=/bin/true git commit --amend --no-edit &> /dev/null
	else
		GIT_EDITOR=/bin/true git cherry-pick --continue --no-edit &> /dev/null
	fi
	if [ $? -ne 0 ]; then
		echo Failed to create new revision for $revision. Aborting
		exit 1
	fi
	echo
done

echo Finished
echo Check the results in the working tree and also the branch history with git log or gitk
echo If you like the results, feel free to move the branch over here \(for example, with \'git branch -f some-branch\'\)
