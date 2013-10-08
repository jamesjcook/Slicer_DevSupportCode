#!/bin/bash
if [ ! -d Slicer ] 
then
    git clone git://github.com/Slicer/Slicer.git;
    cd Slicer;
    git svn init http://svn.slicer.org/Slicer4/trunk;
else
    echo "Found cloned directory";
    cd Slicer;
fi
git update-ref refs/remotes/git-svn refs/remotes/origin/master;
git checkout master;
git svn rebase;
git stash;
git pull;
git stash pop;
cd .. ;

name=`basename $PWD`;
src_path=$PWD/Slicer;
buildbase=/Applications/SegmentationSoftware/build/Slicer_multi/;
cd $buildbase;
mkdir $name;
cd $name;
#-DQT_QMAKE_EXECUTABLE:FILEPATH=/path/to/QtSDK-1.2/Desktop/Qt/474/gcc/bin/qmake 
cmake '-DCMAKE_BUILD_TYPE:STRING=Release' $src_path;
echo cd $buildbase$name;
continue=0;
read -n1 -p 'Pausing before starting compile, now would be a good time to pause execution with ctrl+z and run ccmake to check out the directory. May have to use the echoed cd line above';

while [ continue==0 ] ; do make -sj1 || continue=1; date; echo sleeping for 1 hour; sleep 3600; done
