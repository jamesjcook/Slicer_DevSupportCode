
data_path="DataLibrariesHuman/130827-2-0";
update_name="20170424_nifti";
#nii_file=$(ls $data_path/$update_name/*.nii); # this wont work becuase we dork around with nifti file...
data_file_name="Reg_S64550_labels_20170206"; # for mouse was, "segmentation_04262016smooth";
# several possibilites of v0 ontology exist, 
#ontology_name="civm_human_brainstem_v0_ontology_with_combostructs";  # for mouse was civm_mouse_v2_ontology, dont have an ontology yet...
#ontology_name="civm_human_brainstem_v0_ontology_withlr_and_combostructs";  # for mouse was civm_mouse_v2_ontology, dont have an ontology yet...
#ontology_name="civm_human_brainstem_v0_ontology_withlr";  # for mouse was civm_mouse_v2_ontology, dont have an ontology yet...
ontology_name="civm_human_brainstem_v0_ontology";  # for mouse was civm_mouse_v2_ontology, dont have an ontology yet...
ontology_name_out="civm_human_brainstem_v1_ontology"; # for mouse was civm_mouse_v3_ontology
update_model_file="models_update20170424";# for mouse was "models_update20160426";
# Move old model file to timestamped version so we're not destructive.
if [ -e ${data_path}/models.mrml ]; then
    ts=`stat -f %Sm -t %Y-%m-%d_%H:%M:%s%z ${data_path}/models.mrml`;
    mv ${data_path}/models.mrml ${data_path}/models.mrml.$ts
fi;
if [ -e ${data_path}/models.mrml ]; then
    echo "Error in preserving old files(models)."
    exit;
fi
redo="No";
#redo="yes"
# Generate ModelHierachy.mrml and update lookup table with Hierarchy information from hierarchy spreadsheet.
# We use this updated lookup table for the abbreviations and name versions.
if [ ! -f ${data_path}/${udpate_name}/ModelHierarchy_Structure.mrml -o $redo="yes" ]; then
    ./ontology_hierarchy_creator.pl -o ${data_path}/${udpate_name}/ModelHierarchy_Structure.mrml -m ${data_path}/${update_model_file}.mrml -h ${data_path}/${update_name}/${ontology_name}.csv -c ${data_path}/${update_name}/${data_file_name}.atlas.txt -t Structure

    cp -p ${data_path}/${update_name}/${data_file_name}_Structure_out.atlas.txt ${data_path}/${update_name}/${data_file_name}_fix.txt
    # Copy new hierachy table to fix bad one
    cp -p ${data_path}/${update_name}/${ontology_name}_Structure_out.csv ${data_path}/${update_name}/${ontology_name}_fix.csv
    ontology_name="${ontology_name}_fix";
fi

# Generate ModelHierarchy_Abbrev(just in case).
if [ ! -f ${data_path}/${udpate_name}/ModelHierarchy_Abbrev.mrml -o $redo="yes" ]; then 
    ./ontology_hierarchy_creator.pl -o ${data_path}/${udpate_name}/ModelHierarchy_Abbrev.mrml -m ${data_path}/${update_model_file}.mrml -h ${data_path}/${update_name}/${ontology_name}.csv -c ${data_path}/${update_name}/${data_file_name}_fix.txt -t Abbrev 
fi

# create new atlas.xml from structure out.(could also use the copy called "fix"
if [ ! -f ${data_path}/${update_name}/${data_file_name}_hfe.atlas.xml -o $redo="yes" ]; then 
    /Users/james/svnworkspaces/VoxPortSupport/slicer-to-avizo.pl < ${data_path}/${update_name}/${data_file_name}_fix.txt > ${data_path}/${update_name}/${data_file_name}_hfe.atlas.xml
fi

if [ ! -L ${data_path}/${update_name}/${data_file_name}_hf.nii ]; then 
    mv ${data_path}/${update_name}/${data_file_name}_hf.nii ${data_path}/${update_name}/${data_file_name}_hfe.nii
    ln -s ${data_path}/${update_name}/${data_file_name}_hfe.nii ${data_path}/${update_name}/${data_file_name}_hf.nii
else
    echo "Already linked in";
fi

if [ ! -f ${data_path}/${udpate_name}/ModelHierarchy.mrml ]; then
    ./ontology_hierarchy_creator.pl -o ${data_path}/${udpate_name}/ModelHierarchy.mrml -m ${data_path}/${update_model_file}.mrml -h ${data_path}/${update_name}/${ontology_name}.csv -c ${data_path}/${update_name}/${data_file_name}_fix.txt -t Name
fi

# Get current labels name.
l_p=`ls -t ${data_path}/*labels.nii*|head -n1`;# Only get newest label file
l_n=`basename $l_p`; 
# move old labels and lookup out of way
#label_file=`ls ${data_path}/*labels.nii*`;
if [ ! -L ${data_path}/${l_n%%.*}_lookup.txt ]; then
    t_f="${data_path}/${l_n%%.*}_lookup.txt"; # text file
    ts=`stat -f %Sm -t %Y-%m-%d_%H:%M:%s%z $t_f`; # timesetamp
    mv $t_f $t_f.$ts
else
    echo "Linky label lookup, destroying"
    unlink ${data_path}/$t_f
fi

ts=`stat -f %Sm -t %Y-%m-%d_%H:%M:%s%z $l_p`;
mv ${data_path}/$l_n ${data_path}/$l_n$ts
old_labelfile="${data_path}/$l_n$ts";


# link up new files
pushd `pwd`;
cd ${data_path}/
if [ ! -e `basename $t_f` ]; then
    ln -s ${update_name}/${data_file_name}_fix_Name_out.txt `basename $t_f`;
else
    echo "Error in preserving old files(lookup)."
fi

# if no gzippped labels, then create them from our input lebelfile.
if [ ! -e $l_n ]; then
    l_p=`ls ${update_name}/${data_file_name}_hfe.nii*`
    if [ ${l_p##.*} != "gz" ]; then 
	gzip -c ${l_p} > $l_n.gz;
	oldfile_name=`basename $old_labelfile`;

	DIFF=$(diff $oldfile_name $l_n)
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
if [ ${l_p##.*} != "gz" ]; then # we want this ungzipped.
    cp -vpn $l_p ${update_name}/_feedback/;
else
    if [ ! -f ${update_name}/_feedback/${data_file_name}_hfe.nii  ]; then 
	gunzip -c $l_p > ${update_name}/_feedback/${data_file_name}_hfe.nii ;fi;
fi
    
input_file="${update_name}/${ontology_name}_Structure_out.csv";
dest_file="${update_name}/_feedback/${ontology_name_out}.csv";# start at new destination.
# check diff of new file to input.
DIFF=$(diff ${update_name}/${ontology_name}.csv ${update_name}/${ontology_name}_Structure_out.csv)
if [ "$DIFF" != "" ]; then
    echo "DIFFERENT";
else echo "SAME";
     input_file="${update_name}/${ontology_name}.csv";
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


