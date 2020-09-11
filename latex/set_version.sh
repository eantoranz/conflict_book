#!/bin/bash

if [ $# -lt 1 ]; then
	echo Need to provide a version to use
	exit 1
fi

echo '\providecommand{\versionnumber}{'$1'}' > version.tex

