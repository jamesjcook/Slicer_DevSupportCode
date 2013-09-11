#!/bin/bash

echo Make new extensions with single module named after extension.
go=1
d=`pwd`
if [ "x_$#" != "x_0" ]
then
    echo " procesing group < $@ > with $# elements in group "
    for extension_name in $@
    do 
	cd /Applications/SegmentationSoftware/src/Slicer_multi/modules_comp/Slicer
	ext_create="./Utilities/Scripts/ModuleWizard.py --template ./Extensions/Testing/LoadableExtensionTemplate --target ${d}/${extension_name} ${extension_name}"
	mod_create="./Utilities/Scripts/ModuleWizard.py --template ./Extensions/Testing/LoadableExtensionTemplate/LoadableModuleTemplate --target ${d}/${extension_name}/${extension_name}  ${extension_name}"
	if [ "x_$go" == "x_1" ] 
	then
	    echo $ext_create
	    echo $mod_create
	    $ext_create
	    $mod_create
	    echo edit CMakeLists to include module compiler and not include the default template for the extension
	fi
    done
else
    echo "no args given contentes are:"
    echo $@
fi
