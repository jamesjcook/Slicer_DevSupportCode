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
RELEASE_TYPE=Release
ARCH=x86_64
if [ $1 == i386 ]
then
    ARCH=i386;
    echo Setting i386;
fi
if [ $2 == Debug ]
then
    RELEASE_TYPE=Debug;
    echo Setting Debug;
fi
if [ xx_`echo $name | grep -c release `=="xx_1" ]
then 
    checkout_v=`echo $name | cut -d '_' -f2`;
    echo "Checking out $checkout_v";
    cd Slicer;
    git checkout $checkout_v;
    cd ..;
fi

src_path=$PWD/Slicer;
prefixbase=/Applications/SegmentationSoftware/;
buildbase=$prefixbase/build/Slicer_multi/;
cd $buildbase;
if [ ! -d $name ]
then
    mkdir $name && echo mkdir $name
fi
cd $name;
#-DQT_QMAKE_EXECUTABLE:FILEPATH=/path/to/QtSDK-1.2/Desktop/Qt/474/gcc/bin/qmake 
cmake "-DCMAKE_OSX_ARCHITECTURES:STRING=${ARCH}" "-DCMAKE_INSTALL_PREFIX:STRING=$prefixbase$name" "-DSlicer_REQUIRED_QT_VERSION:STRING=4.8.4" "-DCMAKE_BUILD_TYPE:STRING=${RELEASE_TYPE}" $src_path;
echo cd $buildbase$name;
continue=0;
read -n1 -p 'Pausing before starting compile, now would be a good time to pause execution with ctrl+z and run ccmake to check out the directory. May have to use the echoed cd line above';
date;
while [ continue==0 ] ; do make -sj6 && continue=1; date; echo sleeping for 1 hour; sleep 3600; done
