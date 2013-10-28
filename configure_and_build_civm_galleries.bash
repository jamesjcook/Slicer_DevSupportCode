#!/bin/bash
# ccmake command for life easier



name=`basename $PWD`;
checkout_v=`echo $name | cut -d '_' -f3`;
appdir=/Applications/SegmentationSoftware/release_$checkout_v

BUILD_TYPE=Release
BUILD_ARCH=x86_64
INSTALL_PREFIX=$appdir
SUPERBUILD_SLICER=/Applications/SegmentationSoftware/build/Slicer_multi/${BUILD_TYPE}_${checkout_v}/Slicer-build/ 
#SUPERBUILD_SLICER=/Applications/SegmentationSoftware/build/Slicer_multi/relase_${checkout_v}/Slicer-build/ 
SOURCE_LOCATION=/Applications/SegmentationSoftware/src/GalleryControl_multi/CIVM_GalleryControl


cmake -Wno-dev -DCMAKE_BUILD_TYPE=$BUILD_TYPE -DCMAKE_INSTALL_PREFIX=$INSTALL_PREFIX  -DCMAKE_OSX_ARCHITECTURES=$BUILD_ARCH -DSlicer_DIR=$SUPERBUILD_SLICER $SOURCE_LOCATION

make -sj package