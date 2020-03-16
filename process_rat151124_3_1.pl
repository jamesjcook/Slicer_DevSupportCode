#!/usr/bin/perl
use strict;
use warnings;
use Carp qw(cluck confess croak carp);
use File::Basename;
# use Data::Dump qw(dump);
use Env qw(RADISH_PERL_LIB WORKSTATION_HOME WKS_SETTINGS WORKSTATION_HOSTNAME); # root of radish pipeline folders
if (! defined($RADISH_PERL_LIB)) {
    print STDERR "Cannot find good perl directories, quiting\n";
    #exit $ERROR_EXIT;
}
use lib split(':',$RADISH_PERL_LIB);
use pipeline_utilities;
use civm_simple_util qw(activity_log load_file_to_array get_engine_constants_path printd file_update file_mod_extreme whoami whowasi debugloc sleep_with_countdown $debug_val $debug_locator);# debug_val debug_locator);

# The new ontology that appears complete and should match our lookup table exactly.
my $in_o_csv='I:/RatBrainAtlas/Ontology/Ontology-Rat_v4.2.csv';

# looks like i was running these one at a time, i should emulate that for now.
#my $mrml_endpoint='D:/Libraries/Brain/Rattus_norvegicus/Wistar/RatAvg2019/v2019-06-19/models.mrml';
#my $model_path='D:/Libraries/Brain/Rattus_norvegicus/Wistar/RatAvg2019/v2019-06-19/labels/xmas2015rat_symmetric_cropped/StaticRender';


# The end point mrml file is what will be used by the application. We often star with the same file and run it through several passes of  data reconcilliation/cleanup.
my $mrml_endpoint='D:/Libraries/Brain/Rattus_norvegicus/Wistar/151124_3_1/v2019-04-18/models.mrml';
# Models are hiding in a deeper uglier directory
#D:/Libraries/Brain/Rattus_norvegicus/Wistar/151124_3_1/v2019-04-18/scalars/atlas/labels/xmas2015rat_symmetric_cropped/StaticRender

my $in_color='D:/Libraries/Brain/Rattus_norvegicus/Wistar/151124_3_1/v2019-04-18/scalars/atlas/labels/xmas2015rat_symmetric_cropped/xmas2015_labels_20190614_atlas_lookup.txt';

my ($jnk,$ontology_name,$o_e)=fileparts($in_o_csv,2);
my ($data_path)=dirname($mrml_endpoint);

# Changing the usage for this variable, was formerly a bag of label info. Named for date labels were "finished".
# this one is being labeled mrmlupdate as that is all I expect to have this code update today.
my $update_name="20200316_mrmlupdate";

($jnk,my $label_file_name)=fileparts($in_color,2);
#my $update_model_file="models_update_20181029";

# make our feedback directory where we'll dump a bunch of debugging output.
my $feedback_dir="${data_path}/${update_name}";

my $debug_val=20;# when doing new things, 75 is a good debug value as it will allow us to proceeeede with errors.
my $DEBUGGING="-d $debug_val";
print "This script is not really a general solution, each \"processing\" script is hand crafted for the data in question.\n
FURTHERMORE: the supporting code is often also updated each version in ways which can make them incompatible!!!\n";

die "No models.mrml" if ! -e $mrml_endpoint;
die "No clolor txt" if ! -e $in_color;

my $reprocess=0;#or 1 for true

print("sending feedback to: ${feedback_dir}\n");
if ( ! -d $feedback_dir) { `mkdir ${feedback_dir}`; }

# there were so many challenges with first pass ontology, a script was written to clean up the problems,
# hopefully that'll never be necessary again. WARNING: It is not really a general solution, it is very targed at
# this data and aba ontology as captured.
# use test_tab_sheet_reconciler.bash to run the tab_sheet_reconciler.
#./tab_sheet_reconciler.pl $part $full


###
# create label lookup txt file, tag each label with its value in the name,
###
# This whole concept is messy,
#--Lets skip it and only get the xml converted names.
# .../VoxPortSupport/amira-to-slicer-lbl.pl -xmlin /tmp/$xmlname > ${ln}.atlas.txt`;
# sed -E \'/^[1-9]+/ s/^([0-9]+)[ ](_[0-9]+_)?(.*$)/\1 _\1_\3/\''." ${ln}.atlas.txt > ${ln}.txt
# .../VoxPortSupport/slicer-to-avizo.pl < ${ln}.txt > ${ln}_hf.atlas.xml`;
#folder path

# Generate ModelHierachy.mrml and update lookup table with Hierarchy information from hierarchy spreadsheet.
# We use this updated lookup table for the abbreviations and name versions.
{
    # file older than conversion...
    # ot(older than) is -M file1 > -M file2 (originally thought it'd be <).
    # generate modelhierarchy with the full structure names from the csv
    # rename type
    my $rt="Structure";
    #my $in_mrml="${data_path}/${update_model_file}.mrml";
    my $in_mrml=$mrml_endpoint;
    # structure mrml used for updating spreasheets and stuff.
    my $out_s_mrml="${feedback_dir}/"
        ."ModelHierarchy_${rt}.mrml";
    # temp mrml to be stripped of excess keys and turned into our final product.
    my $out_t_mrml="${data_path}/${update_name}/"
        ."ModelHierarchy.mrml";

    # abbrev_mrml
    #my $out_a_mrml="${data_path}/${update_name}/"
    #    ."ModelHierarchy_Abbrev.mrml";

    #my $in_o_csv="${data_path}/${update_name}/"
    #   ."${ontology_name}.csv";
    # out ontology will have had color and value updated by the input color table.
    my $out_o_csv="${feedback_dir}/"
        ."${ontology_name}_${rt}_out.csv";

    # out_color will have had names udpated by information in the ontology.
    my $out_color="${data_path}/${update_name}/"
        ."${label_file_name}_${rt}_out.txt";
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
    $cmd="./ontology_hierarchy_creator.pl $DEBUGGING  -o $out_s_mrml -m $in_mrml -h $in_o_csv  -g $out_o_csv -c $in_color -t $rt";
    # new run function emulating make file behavior.
    run_on_update($cmd,\@input,\@output);
    die("DEBUGGING: $cmd");
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
    }
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

    #
    # remove excess tractography mrml pieces using the mrml_key_strip
    #
    if( -e $in_tract_mrml ) {
    $script="./mrml_key_strip.pl";
    @input=($script,$in_tract_mrml);
    @output=($out_tract_mrml);
    $cmd="$script $in_tract_mrml modelfile $out_tract_mrml";
    @ks_out=run_on_update($cmd,\@input,\@output);
    } else {
        print("No tractography ($in_tract_mrml).\n");
    }
}
exit 0;
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
