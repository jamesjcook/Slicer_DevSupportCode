#!/bin/bash
# ccmake command for life easier
BUILD_TYPE=Release
BUILD_ARCH=x86_64
INSTALL_PREFIX=/Applications/SegmentationSoftware/release_app
SUPERBUILD_SLICER=/Applications/SegmentationSoftware/build/Slicer_multi/extensions_s_x86_64_itk4_r_130906/Slicer-build/ 
SOURCE_LOCATION=/Applications/SegmentationSoftware/src/GalleryControl_multi/CIVM_GalleryControl


cmake -Wno-dev -DCMAKE_BUILD_TYPE=$BUILD_TYPE -DCMAKE_INSTALL_PREFIX=$INSTALL_PREFIX  -DCMAKE_OSX_ARCHITECTURES=$BUILD_ARCH -DSlicer_DIR=$SUPERBUILD_SLICER $SOURCE_LOCATION

make -sj package