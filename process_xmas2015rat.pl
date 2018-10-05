#!/usr/bin/perl
use strict;
use warnings;
use Carp qw(cluck confess croak carp);
use Data::Dump qw(dump);
use Env qw(RADISH_PERL_LIB WORKSTATION_HOME WKS_SETTINGS WORKSTATION_HOSTNAME ANTSPATH FSLDIR FSLOUTPUTTYPE); # root of radish pipeline folders
if (! defined($RADISH_PERL_LIB)) {
    print STDERR "Cannot find good perl directories, quiting\n";
    #exit $ERROR_EXIT;
}
use lib split(':',$RADISH_PERL_LIB);
use pipeline_utilities;
use civm_simple_util qw(activity_log load_file_to_array get_engine_constants_path printd file_update file_mod_extreme whoami whowasi debugloc sleep_with_countdown $debug_val $debug_locator);# debug_val debug_locator);

my $data_path="DataLibrariesRat/Wistar/Xmas2015Rat/v2018-10-04/";
my $update_name="20181004_update";
my $label_file_name="merge_labels";
my $update_model_file="models_update_20181004";

my $ontology_name="merged_ontologies";
my $ontology_name_out="RatBrain_civm_aba_v0.1_ontology";

#../../v2018-03-13/Labels
my $reference_image="DataLibrariesRat/Wistar/Xmas2015Rat/v2018-03-13/merge_labels.nii";
# make our feedback directory where we'll dump a bunch op debugging output.
my $feedback_dir="${data_path}/${update_name}/_feedback";
if ( ! -d $feedback_dir) { `mkdir ${feedback_dir}`; }

my $debug_val=20;# when doing new things, 75 is a good debug value as it will allow us to proceeeede with errors.
my $DEBUGGING="-d $debug_val";
print "This script is mostly obsolete!!!! Large swaths are ignored\n";

use Cwd;
my $dir = getcwd;
if ( ! -d "$data_path/$update_name/" ) {
    print "Missing dir:$data_path/$update_name/\n";
}
my $reprocess=0;#or 1 for true

###
# find ants
###
if ( not defined $ANTSPATH ) {
    $ANTSPATH="/FAKE_PATH_FOR_SCRIPT";
}
if ( "$ANTSPATH" eq '' ) {
    $ANTSPATH="/FAKE_PATH_FOR_SCRIPT";
}
if  ( ! -d "$ANTSPATH" ) {
    $ANTSPATH="/Volumes/workstation_home/ants_20160816_darwin_11.4/antsbin/bin/";
}
if ( ! -d "$ANTSPATH" ) { 
    $ANTSPATH="/Volumes/workstation_home/usr/bin/";
}
###
# create label lookup txt file, tag each label with its value in the name, 
###
# This whole concept is messy,
#--Lets skip it and only get the xml converted names.
# .../VoxPortSupport/amira-to-slicer-lbl.pl -xmlin /tmp/$xmlname > ${ln}.atlas.txt`;
# sed -E \'/^[1-9]+/ s/^([0-9]+)[ ](_[0-9]+_)?(.*$)/\1 _\1_\3/\''." ${ln}.atlas.txt > ${ln}.txt
# .../VoxPortSupport/slicer-to-avizo.pl < ${ln}.txt > ${ln}_hf.atlas.xml`;
#folder path
my $fp="$data_path/$update_name";
my $labelfile="$fp/$label_file_name.am";
#my $xmlname=`ls -tr $fp/$ln*xml|head -n 1|basename`;chomp($xmlname);
my $xmlname="$label_file_name.atlas.xml";
my $xml=$fp.'/'.$xmlname;
my $avizo_nii="$fp/${label_file_name}.nii";
# Only if we have an am file, and the corresponding nifti and atlas.xml
# If the labelfiles is missing the nifti might be in good shape. 
if ( -f $labelfile && -f $avizo_nii && -f $xml ) {
    #=`find $fp -maxdepth 1 -iname \"*am\" -exec basename \{\} \\;`;chomp($labelfile);    
    my ($UNUSED,$ln,$le)=fileparts($labelfile,2);
    if ( not defined $ln || $ln eq '' ) {
        $ln='*';
    }
    #	my $cmd="/Users/james/svnworkspaces/VoxPortSupport/slicer-to-avizo.pl < $stage2_color > $processed_xml";
    my $script="/Users/james/svnworkspaces/VoxPortSupport/amira-to-slicer-lbl.pl";
    my $txt=$fp.'/'."${ln}.atlas.txt";
    my @input=($script,$xml);
    my @output=($txt);
    my $cmd="$script -xmlin $xml > $txt";
    run_on_update($cmd,\@input,\@output,$reprocess);

    #
    # "fix" label nifti header.
    #
    # This is somewhat optional, however we provide dsistudio loading helpers,
    # SO we want to make sure the labels come up legit when loaded.
    # For the time being, this code is NOT responsible for setting up the 
    # right label file. It only fixes the one it found, and then goes on its way.
    my $ants_nii="$fp/.${label_file_name}_a.nii.gz";
    # Intentionally, and CONFUSINGLY we are going to use the same name for label file that
    # has the right header info on it, just putting it in a sub folder. FSL LIKES TO FORCE GZ!!!
    my $fsl_ext=".nii";
    if ($FSLOUTPUTTYPE =~ /NIFTI_GZ/xi) {
        $fsl_ext=".nii.gz";
    }
    my $fsl_nii="${feedback_dir}/${label_file_name}$fsl_ext";
    #print("creating antsified header on labels\n");
    # MUST FIND REFERENCE FILE!!!!, Previous Labels is ideal!
    #However other matching size images work well. 
    # ANTS HEADER UPDATE COMMANDS BREAK THE DATA. FSL can recover with fslmaths add 0
    # Alternatively, run load_untouch, save_untouch in matlab.
    @input=($avizo_nii,$reference_image);
    @output=($ants_nii);
    $cmd="$ANTSPATH/CopyImageHeaderInformation $reference_image $avizo_nii $ants_nii 1 1 1";
    my @cmd_out=run_on_update($cmd,\@input,\@output);
    # because this operation is so immuteable we'll transfer the timestamp.
    if (scalar(@cmd_out)){
        timestamp_copy($avizo_nii,$ants_nii);
    } else {
        print("Ants labels already available\n");
    }

    #print("using antslabels to create fsl ones at \"correct\" bitdepth\n");
    @input=($ants_nii);
    @output=($fsl_nii);
    $cmd="$FSLDIR/bin/fslmaths $ants_nii -add 0 $fsl_nii  -odt char";
    @cmd_out=run_on_update($cmd,\@input,\@output);
    # originally thought it'd be good to timestamp copy this, 
    # however we have now fixed the header, and kept the original name, so that'll make this confusing.
    if (scalar(@cmd_out)){
    #timestamp_copy($ants_nii,$fsl_nii);
    } else {
        print("fsl fixed labels already available\n");
    }
    
}
# Generate ModelHierachy.mrml and update lookup table with Hierarchy information from hierarchy spreadsheet.
# We use this updated lookup table for the abbreviations and name versions.
{
    # file older than conversion...
    # ot(older than) is -M file1 > -M file2 (originally thought it'd be <).
    # generate modelhierarchy with the full structure names from the csv
    # rename type
    my $rt="Structure";
    my $in_mrml="${data_path}/${update_model_file}.mrml";
    # structure mrml used for updating spreasheets and stuff.
    my $out_s_mrml="${feedback_dir}/"
        ."ModelHierarchy_${rt}.mrml";
    # temp mrml to be stripped of excess keys and turned into our final product.
    my $out_t_mrml="${data_path}/${update_name}/"
        ."ModelHierarchy.mrml";

    # abbrev_mrml
    #my $out_a_mrml="${data_path}/${update_name}/"
    #    ."ModelHierarchy_Abbrev.mrml";
    
    my $in_o_csv="${data_path}/${update_name}/"
        ."${ontology_name}.csv";
    # out ontology will have had color and value updated by the input color table.
    my $out_o_csv="${feedback_dir}/"
        ."${ontology_name}_${rt}_out.csv";

    my $in_color="${data_path}/${update_name}/"
        ."${label_file_name}.atlas.txt";
    # out_color will have had names udpated by information in the ontology.
    my $out_color="${data_path}/${update_name}/"
        ."${label_file_name}.atlas_${rt}_out.txt";
    #  updated xml after we merge info from ontology.
    my $feedback_xml="${feedback_dir}/"
        ."${label_file_name}.atlas.xml";

    # Stage 2 is where we prepare our files for final use, 
    # The stage2 files only exists if the the stage1 outputs were updated.
    my $stage2_onto_name="${ontology_name}_cleaned";
    my $stage2_csv="${data_path}/${update_name}/"
        ."${stage2_onto_name}.csv";
    my $stage2_color="${feedback_dir}/"
        ."${label_file_name}_lookup.txt";
    
    # final output mrml
    my $out_f_mrml="${data_path}/${update_name}/"
        ."ModelHierarchy_modelfile.mrml";
    my $mrml_endpoint="${data_path}/models.mrml";

    my $in_tract_mrml="${data_path}/"
        ."tractography_update.mrml";
    # to prevent inplace crashes while tractography is still broken, we will
    # not update the tractography.mrml file in use. 
    my $out_tract_mrml="${data_path}/"
        ."tractography_update_clean.mrml";
    
    # dsi_studio label names
    my $dsi_studio_label_index="${feedback_dir}/"
        ."${label_file_name}.txt";
    
    ###
    # Clean up discrepancies between ontology and models/labels
    ###
    my $cmd='';
    #my @input=("$in_mrml","$in_o_csv","$in_color");
    my $script="./ontology_hierarchy_creator.pl";
    my @input=($script,$in_mrml,$in_o_csv,$in_color);
    # there are other outputs, but they're more or less opaque
    #my @output=("$out_s_mrml");# there are other outputs, but they're more or less opaque
    my @output=($out_s_mrml);
    $cmd="./ontology_hierarchy_creator.pl $DEBUGGING  -o $out_s_mrml -m $in_mrml -h $in_o_csv -k ABA_abbrev__name -g $out_o_csv -c $in_color -t $rt";
    # new run function emulating make file behavior.
    run_on_update($cmd,\@input,\@output);
    #
    # check if output was updated as expected.
    #
    # This shouldnt be necessary, however the ontology_hierarchy_creator is not particularly compliant.
    my @f=@input;push(@f,@output);
    my $lf=file_mod_extreme(\@f,'new');
    if ($lf ne $out_s_mrml) {
        print "HIERARCHY FAIL\n 
        latest:$lf\n
        is n e\n
        ${out_s_mrml}\n";
        print( (-M $in_o_csv)."\n");
        print( (-M $out_s_mrml)."\n");
        print "$cmd\n";
        die;
    }
    #
    # check if color table changed, if it did, create new xml, and copy to stage 2.
    #
    use File::Compare;
    if (compare($in_color,$out_color) == 0) {
        print("No color table update, will not copy");
        $stage2_color=$in_color;
    } else {
        # IF we updated the color table, .... ? who cares?
        # We havnt produced our final output anyway, lets make that now no matter what.
        my $did_cp=file_update($out_color,$stage2_color);
        my $script="/Users/james/svnworkspaces/VoxPortSupport/slicer-to-avizo.pl";
        @input=($script,$out_color);
        @output=($feedback_xml);
        # .../VoxPortSupport/slicer-to-avizo.pl < ${ln}.txt > ${ln}_hf.atlas.xml`;
        $cmd="$script < $out_color ";
        my @cmd_out=run_on_update($cmd,\@input,\@output);
        if (scalar(@cmd_out)>0 ) { write_array_to_file($feedback_xml,\@cmd_out); 
        } else {
            #die("No update?");
        }
    }die;
    #
    # check if ontology changed, if it did, copy to stage 2.
    #
    use File::Compare;
    if (compare($in_o_csv,$out_o_csv) == 0) {
        print("No ontology update, will not copy");
        $stage2_csv=$in_o_csv;
    } else {
        my $did_cp=file_update($out_o_csv,$stage2_csv);
    }
    @input=($script,$out_s_mrml,$stage2_csv,$stage2_color);
    @output=($out_t_mrml);
    # Copy new hierachy table to use later, and update ontology name.
    $rt="Name";
    $cmd="./ontology_hierarchy_creator.pl $DEBUGGING  -o $out_t_mrml -m $in_mrml -h $stage2_csv -c $stage2_color -t $rt";
    run_on_update($cmd,\@input,\@output);

    #
    # remove excess mrml pieces using the mrml_key_strip
    #
    $script="./mrml_key_strip.pl";
    @input=($script,$out_t_mrml);
    @output=($out_f_mrml);
    $cmd="$script $out_t_mrml";
    my @ks_out=run_on_update($cmd,\@input,\@output);
    if (scalar(@ks_out)){
        print("updated final mrml file $out_f_mrml\n");
    }
    
    #
    # remove excess mrml pieces using the mrml_key_strip
    #
    $script="./mrml_key_strip.pl";
    @input=($script,$in_tract_mrml);
    @output=($out_tract_mrml);
    $cmd="$script $in_tract_mrml modelfile $out_tract_mrml";
    @ks_out=run_on_update($cmd,\@input,\@output);
    
    #
    # move last mrml file out of the way.
    #
    if ( -f $mrml_endpoint ) {
        my $orig_modelfile=move_to_timestamp($mrml_endpoint);
        if (! -f $orig_modelfile || -f $mrml_endpoint ) {
            die "Problem moving $mrml_endpoint to $orig_modelfile";
        }
    }
    # copy final mrml to the endpoint.
    my $cp_mrml=file_update($out_f_mrml,$mrml_endpoint);

    #
    # strip color parts of the colortable to give a name index in dsistudio
    #
    @input=($stage2_color);
    @output=($dsi_studio_label_index);
    $cmd="awk '{print \$1\" \"\$2}' $stage2_color";
    my @l_names=run_on_update($cmd,\@input,\@output);
    if (scalar(@l_names)>0 ) {
        print("writing $dsi_studio_label_index\n");
        write_array_to_file($dsi_studio_label_index,\@l_names);
    } else {
        #die("No update?");
    }
    die;
}
sub run_idealist {
    funct_obsolete("run_idealist","pipeline_utilities::run_on_update");
    return run_on_update(@_);
}

sub file_extreme_alldef {
    # newest (sort{-M $a <=> -M $b }@$a_ref)[0];
    # oldest (sort{-M $b <=> -M $a }@$a_ref)[0];
    my ($a_ref,$dir)=@_;
    if ( $dir eq "new" ){
        return (sort{-M $a <=> -M $b }@$a_ref)[0];
    }elsif ($dir eq "old"){
        return (sort{-M $b <=> -M $a }@$a_ref)[0];
    } else {
        die;
    }
}
sub file_extreme {
    funct_obsolete("file_extreme","civm_simple_util::file_mod_extreme");
    return file_mod_extreme(@_);
}

sub copy_if_older {
    return file_update(@_);
}
sub move_to_timestamp {
    my ($inf,@la)=@_;
    if ( ! -f $inf ){
	print("No existing file to move\n");
	return "";
    } 
    #my $ts=gts($inf);
    my $ts_r=get_timestamp($inf);
    my $ts=$ts_r->{"st_mtime"};
    `mv \"$inf\" \"$inf.$ts\"`;
    if ( -e $inf ) {
	confess "Error in preserving old files.\n";
    }
    return "$inf.$ts";
}
sub gts {
    #get timestamp
    my ($inf,@la)=@_;
    if ( ! -f $inf ){
	print("NOFILE\n");
	return "";
    }
    my $ts=`stat -f %Sm -t %Y-%m-%d_%H:%M:%s%z $inf`;chomp($ts);
    return $ts;
}

__END__
