#!/bin/bash
pushd `pwd`
cd /Applications/SegmentationSoftware/src/GalleryControl_Multi/CIVM_PGR
./uninst.bash
./cmake_command.bash
./inst.bash
popd