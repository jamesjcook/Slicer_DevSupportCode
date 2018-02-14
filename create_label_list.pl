#!/usr/bin/perl
# Create label list files from avizo atlas.xml files.
# fix nifti header of labelfield saved out of avizo.
use strict;
use warnings;
use Env qw(RADISH_PERL_LIB RADISH_RECON_DIR WORKSTATION_HOME WKS_SETTINGS RECON_HOSTNAME WORKSTATION_HOSTNAME ANTSPATH FSLDIR); # root of radish pipeline folders
if (! defined($RADISH_PERL_LIB)) {
    print STDERR "Cannot find good perl directories, quiting\n";
    #exit $ERROR_EXIT;
}
use lib split(':',$RADISH_PERL_LIB);
use pipeline_utilities;
use civm_simple_util qw(activity_log load_file_to_array get_engine_constants_path printd whoami whowasi debugloc sleep_with_countdown $debug_val $debug_locator);# debug_val debug_locator);
###
# set old input label file
###
my $good_header="Reg_S64550_labels.nii.gz";# get last nii in place?
my $good_header_dir="..";
###
# find input files,
# sort out vars for filenames/paths/exts
###
# the am sets the name of the nifti and atlas.xml if its available,
# otherwise get latest xml, and associated nifti.
my $labelfile=`ls -t *am`; chomp($labelfile);
my ($lp,$ln,$le)=fileparts($labelfile,2);
if ( not defined $ln || $ln eq '' ) {
    $ln='*';
}
# oldest xml file
my $xmlname=`ls -tr $ln*xml|head -n 1`; chomp($xmlname);
my ($xp,$xn,$xe)=fileparts($xmlname,2);
# get newest nifti, named just like our xml, using a * in case we've gotten a gzipped variant.
my $label_nii=`ls -tr $xn.nii*|tail -n 1`; chomp($label_nii);
($lp,$ln,$le)=fileparts($label_nii,2);
my ($tp,$tn,$lle)=fileparts($label_nii,3);
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
print "using ants in $ANTSPATH\n";
print "fixing up $label_nii -> ${ln}_hf$le\n";
my $sys=`hostname -s`;chomp($sys);
my $start="";
if ( $sys ne "panorama" ) {
    $start="ssh panorama ";
}

if ( ! -f "${ln}.atlas.txt" 
     || ( -M "${ln}.atlas.txt" > -M "$xmlname" ) 
    ) {
    print "no atlas.txt cowardly quiting\n";
    exit;
    if ( "$start" ne '' ) {
	print "st send xml\n";
	`scp -p $xmlname james\@panorama:/tmp/`;
    } else {
	print "cp xml\n";
	`cp -p $xmlname /tmp/`;
    }
    `$start /Users/james/svnworkspaces/VoxPortSupport/amira-to-slicer-lbl.pl -xmlin /tmp/$xmlname > ${ln}.atlas.txt`;
    `$start rm /tmp/$xmlname`;
}
if ( ! -f "${ln}.txt" 
     || ( -M "${ln}.txt" > -M "${ln}.atlas.txt" ) 
    ) {
    print "numberd list missing, creating\n";
    print "cowardly quiting instead\n";exit;
    `sed -E '/^[1-9]+/ s/^([0-9]+)[ ](_[0-9]+_)?(.*$)/\1 _\1_\3/' ${ln}.atlas.txt > ${ln}.txt`;
}
# Take the fixed up numbers, and put them back into avizo format.
if ( ! -f "${ln}_hf.atlas.xml" 
     || ( -M "${ln}_hf.atlas.xml" > -M "${ln}.txt" ) 
    ) {
    print "back converting xml\n";
    #ln -s ${xmlname} ${ln}_hf.atlas.xml
    #scp -p ${ln}.txt james@panorama:/tmp/;
    `$start /Users/james/svnworkspaces/VoxPortSupport/slicer-to-avizo.pl < ${ln}.txt > ${ln}_hf.atlas.xml`;
    #$start rm /tmp/${ln}.txt;
}
if ( ! -f "${ln}_hf$le" && ! -l "${ln}_hf$le" ) {
    print "${ln}_hf$le not here, so we're creating\n";
    if ( ! -f "${ln}_hf_a.nii" 
	 || ( -M "${ln}_hf_a.nii" > -M "$label_nii" ) 
	) {
	print "creating antsified header on labels\n";
	# ANTS HEADER UPDATE COMMANDS BREAK THE DATA. FSL can recover with fslmaths add 0
	# Alternatively, run load_untouch, save_untouch in matlab.
	`$ANTSPATH/CopyImageHeaderInformation $good_header_dir/$good_header $label_nii ${ln}_hf_a.nii 1 1 1`;
    }
    if ( ! -e "${ln}_hf$le" 
	 || ( -M "${ln}_hf$le" > -M "${ln}_hf_a.nii" ) 
	) {
	print "using antslabels to create fsl ones at correct bitdepth\n";
    	#$ANTSPATH/ConvertImage ${ln}_hf_a.nii ${ln}_hf 0;
	`$FSLDIR/bin/fslmaths ${ln}_hf_a.nii -add 0 ${ln}_hf$le -odt char`;
    }
    if ( ${lle} ne "gz" ) { # do this becuase lots of times fsl gzips our data, silly fsl. This will unzip only if we didnt want it zipped.
	print "unzipping ${ln}_hf$le.gz becuase $lle ne gz. \n";
	`gunzip ${ln}_hf$le.gz`;
    }
    if ( -e "${ln}_hf$le" ) {
	`rm ${ln}_hf_a.nii`;
    } else {
	print "copy header and fslmaths err\n";
    }
}

###
# The complicated remote matlab way to copy header.
###
if ( ! -e "${ln}_hf$le" && "a" eq "b" ) { 

    #
    # start a remote matlab
    #
    `$start /Volumes/workstation_home/software/shared/pipeline_utilities/fifo_start_matlab.pl temp`;
    # copy data
    if ( "$start" ne '' ) {
	`scp -p $good_header_dir/$good_header panorama:/tmp/`;
	`scp -p $label_nii panorama:/tmp/`;
    } else {
	`cp -p $good_header_dir/$good_header /tmp/`;
	`cp -p $label_nii /tmp/`;
    }
    # set up command in a stup file and transfer.
    `echo "run(sprintf('%s/shared/pipeline_utilities/startup.m',getenv('WORKSTATION_HOME')));" >hdr_cp.m`;
    `echo "copyheader_nii('/tmp/$good_header','/tmp/$label_nii');" >>hdr_cp.m`;
    `ehco "system('mv -f /tmp/$label_nii /tmp/${ln}_hf$le');" >>hdr_cp.m`;
    `echo "fprintf('done');" >>hdr_cp.m`;
    if ( "$start" ne '' ) {
	`scp -p hdr_cp.m panorama:/tmp/`;
    } else {
	`cp -p hdr_cp.m /tmp/`;
    }
    # run stub file. 
    `$start "print run\(\'/tmp/hdr_cp\'\)\; >/tmp/temp_fifo"`;
    
    while ( `$start "grep -c done /tmp/temp_fifo.log"` != 1 )  { 
	print '.'; sleep 1; }
    print "\n";
    # stop fifo, this kills our matlab!, must make sure we're done before that!
    `$start /Volumes/workstation_home/software/shared/pipeline_utilities/fifo_stop_matlab.pl temp`;
   # retrieve data
    if ( "$start" ne ''  ) {
	`scp -p panorama:/tmp/${ln}_hf$le ${ln}_hf$le`;
    }
    # clean up remote
    `$start rm /tmp/hdr_cp.m`;
    `$start rm /tmp/temp_fifo`;
    `$start rm /tmp/temp_fifo.log`;
    `$start rm /tmp/$good_header`;
    `$start rm /tmp/$label_nii`;
    
}

# Still need to sort out naming convention, will do by making models and parsing through models.mrml file.
# send this back to james just for gigle.
#scp -rp . james@panorama:~/`basename $PWD`
# in datalibraraies ln -s datafile name_labels.ext and lookup_table.txt name_labels_lookup.txt
#copy to server

print "The next step is to run process_XX.bash script in Slicer_DevSupportCode.\n";
print "WARNING: that code is terribly custom and must be created for each thing.\n";
print "Use proces_mouse_chass as a template for completeness of work.\n";
