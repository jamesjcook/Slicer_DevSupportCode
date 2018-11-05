#!/bin/bash

infile=$1;
outfile=$2;
if [ -z "$infile" ];then
    echo "ERROR: No input to strip.";
    exit 1;
fi;
if [ -z "$outfile" ];then
    echo "ERROR: No output to dump into.";
    exit 1;
fi;

if [ -f $outfile ]; then
    echo "ERROR: existing output, will not over write $outfile !";
    exit 1;
fi;

#sed -i -e 's/few/asd/g' hello.txt
sed -E 's/([ ]*(vtkMRML)?[Ff]iber[Bb]undle([Gg]lyph|[Tt]ube)[Dd]isplay[Nn]ode[0-9]*[ ]*)//g' $infile > $outfile
