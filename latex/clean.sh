#!/bin/bash

# remove all intermediate/output files
rm *.pdf *.html *.log *.lg *.idv *.out *.4ct *.4tc *.dvi *.aux *.css  *.tmp *.xref

if [ -f html ]; then
	rm html -fR
fi

