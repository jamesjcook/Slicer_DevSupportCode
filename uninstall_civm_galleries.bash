#!/bin/bash



pushd `pwd` 
name=`basename $PWD`;
checkout_v=`echo $name | cut -d '_' -f3`;
appdir=/Applications/SegmentationSoftware/release_$checkout_v
tar_file=`ls *tar.gz | tail -n 1`
for file in `tar -tf $tar_file | cut -d '/' -f2-`
do 
    if [ -f $appdir/$file ]
    then
	rm -f $appdir/$file

    else
	echo -n
	echo  "nofile at $appdir/$file"
    fi
done 
popd
echo done!