#!/bin/bash




name=`basename $PWD`;
checkout_v=`echo $name | cut -d '_' -f3`;
appdir=/Applications/SegmentationSoftware/release_$checkout_v
tar_file=`ls -tr *tar.gz | tail -n 1`
for file in `tar -tf $tar_file | cut -d '/' -f2-`
do 
    if [ -f $appdir/$file ]
    then
	echo "found file, $file, cannot run inst"
	exit
    else
	echo -n
	#echo  "nofile at $appdir/$file"
    fi
done 
cp $tar_file $appdir
pushd `pwd` 
cd $appdir && echo cd $appdir && tar --strip-components 1 -kxvf $tar_file
popd
echo "open $appdir/Slicer.app"
open $appdir/Slicer.app