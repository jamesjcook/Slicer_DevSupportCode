
data_path="DataLibrariesMouse/mouse_chass_images/dti";
update_name="20160426_nifti";
#nii_file=$(ls $data_path/$update_name/*.nii); # this wont work becuase we dork around with nifti file...
data_file_name="segmentation_04262016smooth";
ontology_name="civm_mouse_v2_ontology";
ontology_name_out="civm_mouse_v3_ontology";
# Move old model file to timestamped version so we're not destructive.
ts=`stat -f %Sm -t %Y-%m-%d_%H:%M:%s%z ${data_path}/models.mrml`;
mv ${data_path}/models.mrml ${data_path}/models.mrml.$ts
if [ -e ${data_path}/models.mrml ]; then
    echo "Error in preserving old files(models)."
    exit;
fi

# Generate ModelHierachy.mrml and update lookup table with Hierarchy information from hierarchy spreadsheet.
# We use this updated lookup table for the abbreviations and name versions.
if [ ! -f ${data_path}/${udpate_name}/ModelHierarchy_Structure.mrml ]; then
    ./ontology_hierarchy_creator.pl -o ${data_path}/${udpate_name}/ModelHierarchy_Structure.mrml -m ${data_path}/models_update20160426.mrml -h ${data_path}/${ontology_name}.csv -c ${data_path}/${update_name}/${data_file_name}.txt -t Structure

    # Copy new lookup table to fix bad one
    cp -p ${data_path}/${update_name}/${data_file_name}_Structure_out.txt ${data_path}/${update_name}/${data_file_name}_fix.txt 
fi

# Generate ModelHierarchy_Abbrev(just in case).
if [ ! -f ${data_path}/${udpate_name}/ModelHierarchy_Abbrev.mrml ]; then 
    ./ontology_hierarchy_creator.pl -o ${data_path}/${udpate_name}/ModelHierarchy_Abbrev.mrml -m ${data_path}/models_update20160426.mrml -h ${data_path}/${ontology_name}.csv -c ${data_path}/${update_name}/${data_file_name}_fix.txt -t Abbrev 
fi 
# create new atlas.xml from structure out.(could also use the copy called "fix"
if [ ! -f ${data_path}/${update_name}/${data_file_name}_hfe.atlas.xml ]; then 
    /Users/james/svnworkspaces/VoxPortSupport/slicer-to-avizo.pl < ${data_path}/${update_name}/${data_file_name}_Structure_out.txt > ${data_path}/${update_name}/${data_file_name}_hfe.atlas.xml
fi
if [ ! -L ${data_path}/${update_name}/${data_file_name}_hf.nii ]; then 
    mv ${data_path}/${update_name}/${data_file_name}_hf.nii ${data_path}/${update_name}/${data_file_name}_hfe.nii
    ln -s ${data_path}/${update_name}/${data_file_name}_hfe.nii ${data_path}/${update_name}/${data_file_name}_hf.nii
else
    echo "Already linked in";
fi

if [ ! -f ${data_path}/${udpate_name}/ModelHierarchy.mrml ]; then
    ./ontology_hierarchy_creator.pl -o ${data_path}/${udpate_name}/ModelHierarchy.mrml -m ${data_path}/models_update20160426.mrml -h ${data_path}/${ontology_name}.csv -c ${data_path}/${update_name}/${data_file_name}_fix.txt -t Name
fi

# move old labels and lookup out of way
if [ ! -L ${data_path}/dti_labels_lookup.txt ]; then 
    ts=`stat -f %Sm -t %Y-%m-%d_%H:%M:%s%z ${data_path}/dti_labels_lookup.txt`;
    mv ${data_path}/dti_labels_lookup.txt ${data_path}/dti_labels_lookup.txt.$ts
else
    echo "Linky label lookup, destroying"
    unlink ${data_path}/dti_labels_lookup.txt
fi
fp=`ls -t ${data_path}/dti_labels.nii*|head -n1`;# Only get newest label file
ts=`stat -f %Sm -t %Y-%m-%d_%H:%M:%s%z $fp`;
fn=`basename $fp`; 
mv ${data_path}/$fn ${data_path}/$fn$ts
old_labelfile="${data_path}/$fn$ts";


# link up new files
pushd `pwd`;
cd ${data_path}/
if [ ! -e dti_labels_lookup.txt ]; then
    ln -s ${update_name}/${data_file_name}_fix_Name_out.txt dti_labels_lookup.txt
else
    echo "Error in preserving old files(lookup)."
fi
if [ ! -e dti_labels.nii.gz ]; then
    fp=`ls ${update_name}/${data_file_name}_hfe.nii*`
    if [ ${fp##.*} != "gz" ]; then 
	gzip -c ${fp} > dti_labels.nii.gz;
	oldfile_name=`basename $old_labelfile`;

	DIFF=$(diff $oldfile_name dti_labels.nii.gz)
	if [ "$DIFF" != "" ]
	then
	    echo "New label file in place"
	else
	    rm $oldfile_name
	fi
    fi;
else
    echo "Error in preserving old files(labels)."
fi;

# Copy useful files to feed back directyory to be put on workstatiosn. 
if [ ! -d ${update_name}/_feedback ]; then mkdir ${update_name}/_feedback; fi
if [ ${fp##.*} != "gz" ]; then # we want this ungzipped.
    cp -vpn $fp ${update_name}/_feedback/;
else
    if [ ! -f ${update_name}/_feedback/${data_file_name}_hfe.nii  ]; then 
	gunzip -c $fp > ${update_name}/_feedback/${data_file_name}_hfe.nii ;fi;
fi
    
input_file="${update_name}/${ontology_name}_Structure_out.csv";
dest_file="${update_name}/_feedback/${ontology_name_out}.csv";# start at new destination.
# check diff of new file to input.
DIFF=$(diff ${ontology_name}.csv ${update_name}/${ontology_name}_Structure_out.csv)
if [ "$DIFF" != "" ]; then
    echo "DIFFERENT";
else echo "SAME";
     input_file="${ontology_name}.csv";
     if [ -f $dest_file ]; then
	 rm $dest_file;
     fi;
     dest_file="${update_name}/_feedback/${ontology_name}.csv";
     ontology_name_out=$ontology_name;
fi;

function copy_if_older ()
{
    input_file=$1;
    dest_file=$2;
    DIFF="Missing";
    if [ -f $dest_file ]; then 
	DIFF=$(diff $input_file $dest_file);
    fi
    if [ "$DIFF" != "" ]; then
	#diff, now check older. 
	if [ -f $dest_file ]; then
	    input_epoc=$(date -r "$input_file" +%s)
	    dest_epoc= $(date -r  "$dest_file" +%s)
	    if (( $dest_epoc < $input_epoc )); then
		ts=`stat -f %Sm -t %Y-%m-%d_%H:%M:%s%z $dest_file`;
	 	mv -v $dest_file $dest_file$ts
	    fi;
	fi;
	cp -vpn $input_file $dest_file;
    else
	#same
	echo  "No copy, files are the same.";
    fi
    return;
}

copy_if_older $input_file $dest_file ;
copy_if_older ${update_name}/${ontology_name}_Structure_Lists_out.headfile ${update_name}/_feedback/${ontology_name_out}_Structure_to_leaf.headfile ;
copy_if_older ${update_name}/${ontology_name}_Structure_Lists_out.csv ${update_name}/_feedback/${ontology_name_out}_Structure_to_leaf.csv ;
copy_if_older ${update_name}/${data_file_name}_fix_Abbrev_out.txt ${update_name}/_feedback/${data_file_name}_abbrev_labels_lookup.txt ;
copy_if_older ${update_name}/${data_file_name}_Name_out.txt       ${update_name}/_feedback/${data_file_name}_name_labels_lookup.txt ;
copy_if_older ${update_name}/${data_file_name}_Structure_out.txt  ${update_name}/_feedback/${data_file_name}_labels_lookup.txt ;
copy_if_older ${update_name}/${data_file_name}_hfe.atlas.xml      ${update_name}/_feedback/${data_file_name}_hfe.atlas.xml ;
popd;

#if [ ! -f 
./mrml_key_strip.pl ${data_path}/${udpate_name}/ModelHierarchy.mrml
mv ${data_path}/${udpate_name}/ModelHierarchy_modelfile.mrml ${data_path}/models.mrml


