#!/usr/bin/perl
# Create label list files from avizo atlas.xml files.
# fix nifti header of labelfield saved out of avizo.
use strict;
use warnings;
use Env qw(RADISH_PERL_LIB RADISH_RECON_DIR WORKSTATION_HOME WKS_SETTINGS RECON_HOSTNAME WORKSTATION_HOSTNAME ANTSPATH); # root of radish pipeline folders
if (! defined($RADISH_PERL_LIB)) {
    print STDERR "Cannot find good perl directories, quiting\n";
    #exit $ERROR_EXIT;
}
use lib split(':',$RADISH_PERL_LIB);
use pipeline_utilities;
use civm_simple_util qw(activity_log load_file_to_array get_engine_constants_path printd whoami whowasi debugloc sleep_with_countdown $debug_val $debug_locator);# debug_val debug_locator);



my $labelfile=`ls -t *am`;
if ( not defined $labelfile || $labelfile eq '' ) {
    $labelfile='*';
}
my $xmlname=`ls -t $labelfile*xml|tail -n 1`;# get oldest xml cuz sort newest first
my $avizo_nii=`ls -tr ${xmlname%%.*}.nii*|tail -n 1`; # in case we've gotten a gzipped variant. 
my $nii_with_good_header="${avizo_nii%%.*}_hf.${avizo_nii#*.}";


my $good_header="Reg_S64550_labels.nii.gz";# get last nii in place?
my $good_header_dir="..";

if ( -z "$ANTSPATH" -o ! -d "$ANTSPATH" ) {
    $ANTSPATH="/Volumes/workstation_home/ants_20160816_darwin_11.4/antsbin/bin/";
}
if ( ! -d $ANTSPATH ) { 
    $ANTSPATH="/Volumes/workstation_home/usr/bin/";
}
print "using ants in $ANTSPATH";
print "fixing up $avizo_nii -> $nii_with_good_header";
exit;
my $sys=`hostname -s`;
start="";
if ( $sys != panorama ) {
    start="ssh panorama ";
}
if ( ! -f ${avizo_nii%%.*}.atlas.txt ) {
    if ( ! -z "$start" ) { 
	scp -p $xmlname james@panorama:/tmp/;
    } else {
	cp -p $xmlname /tmp/;
    }
    $start /Users/james/svnworkspaces/VoxPortSupport/amira-to-slicer-lbl.pl -xmlin /tmp/$xmlname > ${avizo_nii%%.*}.atlas.txt;
    $start rm /tmp/$xmlname;
}

if ( ! -f ${avizo_nii%%.*}.txt ) { 
    sed -E '/^[1-9]+/ s/^([0-9]+)[ ](_[0-9]+_)?(.*$)/\1 _\1_\3/' ${avizo_nii%%.*}.atlas.txt > ${avizo_nii%%.*}.txt;
}

# Take the fixed up numbers, and put them back into avizo format.
if ( ! -f ${nii_with_good_header%%.*}.atlas.xml ) {
    #ln -s ${xmlname} ${nii_with_good_header%%.*}.atlas.xml
    #scp -p ${avizo_nii%%.*}.txt james@panorama:/tmp/;
    $start /Users/james/svnworkspaces/VoxPortSupport/slicer-to-avizo.pl < ${avizo_nii%%.*}.txt > ${nii_with_good_header%%.*}.atlas.xml
    #$start rm /tmp/${avizo_nii%%.*}.txt;
}

if ( ! -f ${nii_with_good_header} ) {
    if ( ! -f ${avizo_nii%%.*}_hf_a.nii ) {
	# ANTS HEADER UPDATE COMMANDS BREAK THE DATA. FSL can recover with fslmaths add 0
	# Alternatively, run load_untouch, save_untouch in matlab.
	$ANTSPATH/CopyImageHeaderInformation $good_header_dir/$good_header $avizo_nii ${avizo_nii%%.*}_hf_a.nii 1 1 1
    }
    if ( ! -f $nii_with_good_header ) {
    	#$ANTSPATH/ConvertImage ${avizo_nii%%.*}_hf_a.nii $nii_with_good_header 0;
	$FSLDIR/bin/fslmaths ${avizo_nii%%.*}_hf_a.nii -add 0 $nii_with_good_header -odt char;
    }
    if ( ${nii_with_good_header##.*} != "gz" ) { # do this becuase lots of times fsl gzips our data, silly fsl. This will unzip only if we didnt want it zipped.
	gunzip ${nii_with_good_header}.gz;
    }
    if ( -f ${nii_with_good_header} ) {
	rm ${avizo_nii%%.*}_hf_a.nii
    } else {
	print "copy header and fslmaths err"
    }
}
###
# The complicated remote matlab way to copy header.
###
if ( ! -f ${nii_with_good_header} -a "a" == "b" ) { 

    #
    # start a remote matlab
    #
    $start /Volumes/workstation_home/software/shared/pipeline_utilities/fifo_start_matlab.pl temp
    # copy data
    if ( ! -z "$start" ) {
	scp -p $good_header_dir/$good_header panorama:/tmp/;
	scp -p $avizo_nii panorama:/tmp/;
    } else {
	cp -p $good_header_dir/$good_header /tmp/;
	cp -p $avizo_nii /tmp/;
    }
    # set up command in a stup file and transfer.
    print "run(sprintf('%s/shared/pipeline_utilities/startup.m',getenv('WORKSTATION_HOME')));" >hdr_cp.m;
    print "copyheader_nii('/tmp/$good_header','/tmp/$avizo_nii');" >>hdr_cp.m;
    print "system('mv -f /tmp/$avizo_nii /tmp/${nii_with_good_header}');" >>hdr_cp.m;
    print "fprintf('done');" >>hdr_cp.m;
    if ( ! -z "$start" ) {
	scp -p hdr_cp.m panorama:/tmp/;
    } else {
	cp -p hdr_cp.m /tmp/;
    }
    # run stub file. 
    $start "print run\(\'/tmp/hdr_cp\'\)\; >/tmp/temp_fifo";
    
    while ( `$start "grep -c done /tmp/temp_fifo.log"` -ne 1 );  do 
    print -n "."; sleep 1; done
    print "";
    # stop fifo, this kills our matlab!, must make sure we're done before that!
    $start /Volumes/workstation_home/software/shared/pipeline_utilities/fifo_stop_matlab.pl temp
    # retrieve data
    if ( ! -z "$start" ) {
	scp -p panorama:/tmp/${nii_with_good_header} $nii_with_good_header;
    }
    # clean up remote
    $start rm /tmp/hdr_cp.m
    $start rm /tmp/temp_fifo
    $start rm /tmp/temp_fifo.log
    $start rm /tmp/$good_header
    $start rm /tmp/$avizo_nii
    
}

# Still need to sort out naming convention, will do by making models and parsing through models.mrml file.
# send this back to james just for gigle.
#scp -rp . james@panorama:~/`basename $PWD`
# in datalibraraies ln -s datafile name_labels.ext and lookup_table.txt name_labels_lookup.txt
#copy to server

print "The next step is to run process_XX.bash script in Slicer_DevSupportCode."
print "WARNING: that code is terribly custom and must be created for each thing."
print "Use proces_mouse_chass as a template for completeness of work."
