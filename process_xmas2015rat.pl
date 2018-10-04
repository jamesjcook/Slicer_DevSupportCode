#!/usr/bin/perl
use strict;
use warnings;
use Env qw(RADISH_PERL_LIB RADISH_RECON_DIR WORKSTATION_HOME WKS_SETTINGS RECON_HOSTNAME WORKSTATION_HOSTNAME); # root of radish pipeline folders
if (! defined($RADISH_PERL_LIB)) {
    print STDERR "Cannot find good perl directories, quiting\n";
}
use lib split(':',$RADISH_PERL_LIB);
use pipeline_utilities;
use civm_simple_util qw(activity_log load_file_to_array get_engine_constants_path printd whoami whowasi debugloc sleep_with_countdown $debug_val $debug_locator);# debug_val debug_locator);

my $data_path="DataLibrariesRat/Wistar/Xmas2015Rat/v2018-10-04/";
#my $update_name="20171211_update";
my $update_name="20181004_update";
my $label_file_name="merge_labels";


my $update_model_file="models_update_20181004";
#RatBrain_BadeaPaxinos_ontology_v3.2.xls

# set in ontology path, and out
my $in_o_csv ="DataLibrariesMouse/C57BL_6J/half_25UM/v2017-09-29/civm_mouse_v2_ontology.csv";
my $ontology_name="RatBrain_civm_v2.0_ontology";
my $ontology_name_out="RatBrain_civm_v2.1_ontology";
my $out_o_csv="$data_path/RatBrain_civm_v2.1_ontology_Structure_out.csv";
my $in_color=    "${data_path}/${update_name}/${label_file_name}_lookup.txt";
my $out_color=   "${data_path}/${update_name}/${label_file_name}_lookup_Structure_out.txt";
my $stage2_color="${data_path}/${update_name}/${label_file_name}_lookup_fix.txt";
die;

my $debug_val=75;# when doing new things, 75 is a good debug value as it will allow us to proceeeede with errors.
my $DEBUGGING="-d $debug_val";

if ( 0 ) { 
###
# create label list
###
use Cwd;
my $dir = getcwd;
if ( ! -d "$data_path/$update_name/" ) {
    print "Missing dir:$data_path/$update_name/\n";
}
chdir "$data_path/$update_name/";
print "$dir\n";
print "$dir/create_label_list.pl\n";
my $c="$dir/create_label_list.pl";
my $out=runner($c);
chdir($dir);
}
my $reprocess="No";
#$reprocess="yes";
# Generate ModelHierachy.mrml and update lookup table with Hierarchy information from hierarchy spreadsheet.
# We use this updated lookup table for the abbreviations and name versions.

{
    # file older than conversion...
    # ot(older than) is -M file1 > -M file2 (originally thought it'd be <).
    # generate modelhierarchy with the full structure names from the csv
    my $in_mrml="${data_path}/${update_model_file}.mrml";
    my $out_t_mrml="${data_path}/${update_name}/ModelHierarchy.mrml";
    my $out_s_mrml="${data_path}/${update_name}/ModelHierarchy_Structure.mrml";
    my $out_a_mrml="${data_path}/${update_name}/ModelHierarchy_Abbrev.mrml";

    ###
    # check inputs area available
    ###
    if ( ! -f $in_o_csv
	 || ! -f $in_color
	 || ! -f $in_mrml ) {
	if ( ! -f $in_o_csv ){ print "missing:".$in_o_csv."\n"; }
	if ( ! -f $in_color){  print "missing:".$in_color."\n"; }
	if ( ! -f $in_mrml ) { print "missing:".$in_mrml."\n"; }
	exit; 
    }
    if ( ( ! -f $out_s_mrml || $reprocess eq "yes" )
	 || ( -M $out_s_mrml > -M $in_mrml )
	 || ( -M $out_s_mrml > -M $in_o_csv )
	 || ( -M $out_s_mrml > -M $in_color ) ) {
	if ( ! -f $out_s_mrml ){ print "unprocessed\n"; }
	if ( $reprocess eq "yes"){ print "reprocess yes\n"; }
	if ( -f $out_s_mrml ) {
	    if ( -M $out_s_mrml > -M $in_mrml  ) { print "newer mrml\n"; }
	    if ( -M $out_s_mrml > -M $in_o_csv ) { print "newer csv\n"; }
	    if ( -M $out_s_mrml > -M $in_color ) { print "newer txt"; }
	}
	my $cmd="./ontology_hierarchy_creator.pl $DEBUGGING -g $out_o_csv -o $out_s_mrml -m $in_mrml -h $in_o_csv -c $in_color -t Structure";
	print("$cmd\n");
	`$cmd`;
	if ( ! -f $out_color   
	     || ( -M $out_color > -M $in_o_csv )
	     || ( -M $out_color > -M $in_mrml  )
	     || ( -M $out_color > -M $in_color )
	    ) {
	    print "HIERARCHY FAIL\n";
	    print "no out color $out_color, or its older than input csv $in_o_csv.\n";
	    print( (-M $out_color)."\n");
	    print( (-M $in_o_csv)."\n");
	    #print "$cmd\n"; # we already printed it :p
	    exit;
	}
	$cmd="cp -p $out_color $stage2_color";
	`$cmd`;
	# Copy new hierachy table to fix bad one
	$cmd="cp -p $out_o_csv ${data_path}/${update_name}/${ontology_name}_fix.csv";
	`$cmd`;
	$ontology_name="${ontology_name}_fix";
	# Generate ModelHierarchy_Abbrev(just in case).
	if ( ( ! -f $out_a_mrml ) 
	     || ! -f $stage2_color
	     || ( $reprocess = "yes" ) 
	     || ( -M $out_a_mrml > -M $out_s_mrml ) ) {
	    $cmd=`./ontology_hierarchy_creator.pl $DEBUGGING -o $out_a_mrml -m $in_mrml -h $in_o_csv -c $stage2_color -t Abbrev `;
	    `$cmd`;
	}
    }
    # create new atlas.xml from structure out.(could also use the copy called "fix"
    my $processed_xml="${data_path}/${update_name}/${label_file_name}_hfe.atlas.xml";
    if( ( ( ! -f $processed_xml ) || ( $reprocess eq "yes" )  )
	|| ( -M $processed_xml > -M $stage2_color ) ) {
	print("creating processed_xml $processed_xml\n");
	#print( (-M $processed_xml)."\n".(-M $stage2_color)."\n");
	my $cmd="/Users/james/svnworkspaces/VoxPortSupport/slicer-to-avizo.pl < $stage2_color > $processed_xml";
	print($cmd."\n");
	`$cmd`;
    } else {
	print("processed xml ready\n");
    }

    my $fixed_label_file="${data_path}/${update_name}/${label_file_name}_hf.nii";
    my $processed_label_file="${data_path}/${update_name}/${label_file_name}_hfe.nii";
    if ( ! -l $fixed_label_file ){  
	my $cmd="mv $fixed_label_file $processed_label_file ".
	    "&& ln -s $processed_label_file $fixed_label_file";
	`$cmd`;
    } else {
	print "Already linked in\n";
    }

    if ( ( ( ! -f $out_t_mrml ) || ( $reprocess eq "yes" ) )
	 || ( -M $out_t_mrml > -M  $out_s_mrml ) ) {
	my $cmd="./ontology_hierarchy_creator.pl $DEBUGGING -o $out_t_mrml -m $in_mrml -h $in_o_csv -c $stage2_color -t Name";
	`$cmd`;
    }

    if ( 0 ) {
    # Get current labels name.
    my $l_p=`ls -t ${data_path}/*labels*nii*|head -n1`;# Only get newest label file
    chomp($l_p);
    #my $l_n=`basename $l_p`;
    my ($x,$l_n,$e)=fileparts($l_p,2);
    # move old labels and lookup out of way
    #my $t_f="${data_path}/${l_n%%.*}_lookup.txt"; # text file
    my $t_f=$x.$l_n."_lookup.txt";
    if ( -e $t_f  ){
	if ( ! -l "$t_f" ) {
	    my $ts=gts($t_f);
	    my $a_f=$data_path.$l_n."_lookup".$ts.".txt";
	    if ($ts ne "" &&  -e $a_f ){
		print "moving $t_f -> $a_f\n";
		`mv $t_f $a_f`;
	    } else {
		print("label lookup hasnt changed.\n");
		`rm $a_f`;
	    }
	} else {
	    print "Linky label lookup, destroying\n";
	    `unlink $t_f`; #${data_path}/
	}
    } # else, we've probably already moved out of the way.
    my $ts=gts($l_p);
    chomp($ts);
    #my $old_labelfile="${data_path}/${l_n%%.*}$ts.${ln#*.}";
    my $old_labelfile=$x.$l_n.".".$ts.$e;
    if ( $l_p =~ /$ts/x ) { #the timestamp is in our name, eg, its already been moved.
	#print(join("\n",($l_n,$l_p,$old_labelfile)));
	print("Already moved $l_n\n");
	$old_labelfile=$l_p;
    } else {
	`mv $l_p $old_labelfile`;
    }
    use Cwd;
    my $od=fastcwd();
    chdir "${data_path}/";
    my ($ul_p,$ul_d,$ul_n,$ul_e);
    $ul_p=`ls ${update_name}/${label_file_name}_hfe.nii*`;chomp($ul_p);
    ($ul_d,$ul_n,$ul_e)=fileparts($ul_p,2);
    {
	# link up new files
	#use File::pushd;
	#pushd fastcwd();#`pwd`;
	
	#my $durr=pushd("${data_path}/");
	my ($t_p,$t_n,$t_e)=fileparts($t_f,2);
	if (! -e $t_n.$t_e ) {
	    print "Copying new lookup in \n";
	    `cp -p ${update_name}/${label_file_name}_fix_Name_out.txt $t_n$t_e`;
	} else {
	    print "Error in preserving old files(lookup).\n";
	}
	# if no gzippped labels, then create them from our input lebelfile.
	if (! -e "$l_n*" ) {# need to fix this l_n to include appropriate ext
	    if ($ul_e !~ /gz$/x ) {
		print "$ul_p is not gzipped.\n";
		`gzip -c ${ul_p} > $l_n.nii.gz`;
		my $oldfile_name=`basename $old_labelfile`; chomp($oldfile_name);
		print "checking if labels are different\n";
		print "$data_path diff $oldfile_name ${l_n}.nii.gz\n";
		my $DIFF=`diff "$oldfile_name" "${l_n}.nii.gz"`;chomp($DIFF);
		if ("$DIFF" eq "") {
		    print"New label file in place\n";
		} else {
		    `echo rm $oldfile_name`;
		}
	    }
	} else {
	    print "Error in preserving old files(labels)."
	}
    }
    
    # Copy useful files to feed back directyory to be put on workstatiosn. 
    if ( ! -d "${update_name}/_feedback" ) { `mkdir ${update_name}/_feedback`; }
    if ( $ul_e !~ /gz$/ ) { # we want this ungzipped.
	print("New not gzipped, just sending it to feedback\n");
	`cp -vpn $ul_p ${update_name}/_feedback/`;
    } else {
	if ( ! -f "${update_name}/_feedback/${label_file_name}_hfe.nii"  ) { 
	    `gunzip -c $ul_p > ${update_name}/_feedback/${label_file_name}_hfe.nii`;
	}
    }
    my $input_file="${update_name}/${ontology_name}_Structure_out.csv";
    my $dest_file="${update_name}/_feedback/${ontology_name_out}.csv";# start at new destination.
    # check diff of new file to input.
    my $DIFF=`diff ${update_name}/${ontology_name}.csv ${update_name}/${ontology_name}_Structure_out.csv`;chomp $DIFF;
    if ( "$DIFF" ne "" ) {
	print "DIFFERENT ($DIFF)\n\n\t Label update happened!\n";
    } else { 
	print "SAME\n";
	$input_file="${update_name}/${ontology_name}.csv";
	if ( -f $dest_file ) {
	    `rm $dest_file`;
	}
	$dest_file="${update_name}/_feedback/${ontology_name}.csv";
	$ontology_name_out=$ontology_name;
    }
    
    copy_if_older("$input_file","$dest_file");
    copy_if_older("${update_name}/${ontology_name}_Structure_Lists_out.headfile","${update_name}/_feedback/${ontology_name_out}_Structure_to_leaf.headfile");
    copy_if_older("${update_name}/${ontology_name}_Structure_Lists_out.csv","${update_name}/_feedback/${ontology_name_out}_Structure_to_leaf.csv");
    copy_if_older("${update_name}/${label_file_name}_fix_Abbrev_out.txt","${update_name}/_feedback/${label_file_name}_abbrev_labels_lookup.txt" );
    copy_if_older("${update_name}/${label_file_name}_fix_Name_out.txt","${update_name}/_feedback/${label_file_name}_name_labels_lookup.txt ");
    copy_if_older("${update_name}/${label_file_name}.atlas_Structure_out.txt","${update_name}/_feedback/${label_file_name}_labels_lookup.txt");
    copy_if_older("${update_name}/${label_file_name}_hfe.atlas.xml","${update_name}/_feedback/${label_file_name}_hfe.atlas.xml");
    chdir $od;#popd;
    }
#if [ ! -f 
    `./mrml_key_strip.pl $out_t_mrml`;

    
    # Move old model file to timestamped version so we're not destructive.
    my $orig_modelfile=move_to_timestamp("${data_path}/models.mrml");
    if ( -f "${data_path}/${update_name}/ModelHierarchy_modelfile.mrml" ) {
	`mv ${data_path}/${update_name}/ModelHierarchy_modelfile.mrml ${data_path}/models.mrml`;
    } elsif( $orig_modelfile ne "" ) {
	`mv $orig_modelfile ${data_path}/models.mrml`;
    }
}

sub runner {
    # this doesnt quite work : (
    # the idea was a run and watch like we're right in the shell.
    # the inital problem was the capture missed stderr, 
    # this is what was thrown in here in ~30 seconds, but it doesnt operated as expected.
    my($c,@a)=@_;
    my @out;
    my $pid = open(my $PH, "$c 3>&1 1>&2 2>&3 3>&-|");
    while (<$PH>) {
	print $_;
	push(@out,$_);
    }
    return @out;
}
sub copy_if_older {
    my ($f1,$f2) = @_;
    if ( ! -f $f1 ) {
	print("missing file \n\t$f1\n");
	return; }
    my $docp=1;
    if ( -f $f2 ) { 
	if ( -M $f1 >= -M  $f2 ) {
	    print ( ( -M $f1 )."ot".(-M $f2)."\n");
	    $docp=0;
	} 
    }
    if ($docp){`cp -p $f1 $f2`;}
    return;
}
sub move_to_timestamp {
    my ($inf,@la)=@_;
    if ( ! -f $inf ){
	print("No existing file to move\n");
	return "";
    } 
    my $ts=gts($inf);
    `mv \"$inf\" \"$inf.$ts\"`;
    if ( -e $inf ) {
	print "Error in preserving old files.\n";
	exit;
    }
    return "$inf.$ts";
}
sub gts {
    my ($inf,@la)=@_;
    if ( ! -f $inf ){
	print("NOFILE\n");
	return "";
    }
    my $ts=`stat -f %Sm -t %Y-%m-%d_%H:%M:%s%z $inf`;chomp($ts);
    return $ts;
}

__END__
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
	    if [ $input_file -nt $dest_file ]; then
		ts=`stat -f %Sm -t %Y-%m-%d_%H:%M:%s%z $dest_file`;
	 	mv -v $dest_file $dest_file$ts
	    fi;
	fi;
	cp -vpn $input_file $dest_file;
    else
	#same
	echo  "No copy, files are the same.($input_file, $dest_file)";
    fi
    return;
}

}
__END__  

