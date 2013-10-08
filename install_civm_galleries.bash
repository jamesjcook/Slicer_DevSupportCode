#!/bin/bash
appdir=/Applications/SegmentationSoftware/release_app
tar_file=`ls -tr *tar.gz | tail -n 1`
for file in `tar -tf $tar_file | cut -d '/' -f2-`
# Slicer.app/Contents/Extensions-22287/CIVM_PGR/lib/Slicer-4.3/qt-loadable-modules/libqSlicerCIVM_PGRModule.dylib Slicer.app/Contents/Extensions-22287/CIVM_PGR/lib/Slicer-4.3/qt-loadable-modules/libqSlicerCIVM_PGRModuleWidgets.dylib Slicer.app/Contents/Extensions-22287/CIVM_PGR/lib/Slicer-4.3/qt-loadable-modules/libqSlicerLoadableModuleTemplateModule.dylib Slicer.app/Contents/Extensions-22287/CIVM_PGR/lib/Slicer-4.3/qt-loadable-modules/libqSlicerLoadableModuleTemplateModuleWidgets.dylib Slicer.app/Contents/Extensions-22287/CIVM_PGR/lib/Slicer-4.3/qt-loadable-modules/libvtkSlicerCIVM_PGRModuleLogic.dylib Slicer.app/Contents/Extensions-22287/CIVM_PGR/lib/Slicer-4.3/qt-loadable-modules/libvtkSlicerCIVM_PGRModuleLogicPythonD.dylib Slicer.app/Contents/Extensions-22287/CIVM_PGR/lib/Slicer-4.3/qt-loadable-modules/libvtkSlicerLoadableModuleTemplateModuleLogic.dylib Slicer.app/Contents/Extensions-22287/CIVM_PGR/lib/Slicer-4.3/qt-loadable-modules/libvtkSlicerLoadableModuleTemplateModuleLogicPythonD.dylib Slicer.app/Contents/Extensions-22287/CIVM_PGR/lib/Slicer-4.3/qt-loadable-modules/Python/vtkSlicerCIVM_PGRModuleLogic.py Slicer.app/Contents/Extensions-22287/CIVM_PGR/lib/Slicer-4.3/qt-loadable-modules/Python/vtkSlicerCIVM_PGRModuleLogic.pyc Slicer.app/Contents/Extensions-22287/CIVM_PGR/lib/Slicer-4.3/qt-loadable-modules/Python/vtkSlicerLoadableModuleTemplateModuleLogic.py Slicer.app/Contents/Extensions-22287/CIVM_PGR/lib/Slicer-4.3/qt-loadable-modules/Python/vtkSlicerLoadableModuleTemplateModuleLogic.pyc Slicer.app/Contents/Extensions-22287/CIVM_PGR/lib/Slicer-4.3/qt-loadable-modules/qSlicerCIVM_PGRModuleWidgetsPythonQt.so Slicer.app/Contents/Extensions-22287/CIVM_PGR/lib/Slicer-4.3/qt-loadable-modules/qSlicerLoadableModuleTemplateModuleWidgetsPythonQt.so Slicer.app/Contents/Extensions-22287/CIVM_PGR/lib/Slicer-4.3/qt-loadable-modules/vtkSlicerCIVM_PGRModuleLogicPython.so Slicer.app/Contents/Extensions-22287/CIVM_PGR/lib/Slicer-4.3/qt-loadable-modules/vtkSlicerLoadableModuleTemplateModuleLogicPython.so Slicer.app/Contents/Extensions-22287/CIVM_PGR/share/Slicer-4.3/CIVM_PGR.s4ext
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