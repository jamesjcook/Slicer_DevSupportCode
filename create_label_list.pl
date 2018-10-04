#!/usr/bin/perl
# Create label lookup files from avizo atlas.xml files.
# 
use strict;
use warnings;
use Cwd;
use Env qw(RADISH_PERL_LIB RADISH_RECON_DIR WORKSTATION_HOME WKS_SETTINGS RECON_HOSTNAME WORKSTATION_HOSTNAME ANTSPATH FSLDIR); # root of radish pipeline folders
if (! defined($RADISH_PERL_LIB)) {
    print STDERR "Cannot find good perl directories, quiting\n";
    #exit $ERROR_EXIT;
}
use lib split(':',$RADISH_PERL_LIB);
use pipeline_utilities;
use civm_simple_util qw(activity_log load_file_to_array get_engine_constants_path printd whoami whowasi debugloc sleep_with_countdown $debug_val $debug_locator);# debug_val debug_locator);

die "This code is obsolete! proces_xx.pl sohuld be created/updated, see human brainstem for starter.";
###
# are we on james's computer or not.
###
my $sys=`hostname -s`;chomp($sys);
my $start="";
if ( $sys ne "indelicate" ) {
    $start="ssh indelicate ";
}
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
if ( ! -f "${ln}.atlas.txt" 
     || ( -M "${ln}.atlas.txt" > -M "$xmlname" ) 
    ) {
    print "no ${ln}.atlas.txt, creating\n";
    if ( "$start" ne '' ) {
	print "st send xml\n";
	`scp -p $xmlname james\@indelicate:/tmp/`;
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
    print "numberd list missing ${ln}.txt, creating\n";
    print (getcwd."\n");
    my $sconv='sed -E \'/^[1-9]+/ s/^([0-9]+)[ ](_[0-9]+_)?(.*$)/\1 _\1_\3/\''." ${ln}.atlas.txt > ${ln}.txt";
    print("$sconv\n");
}
# Take the fixed up numbers, and put them back into avizo format.
if ( ! -f "${ln}_hf.atlas.xml" 
     || ( -M "${ln}_hf.atlas.xml" > -M "${ln}.txt" ) 
    ) {
    print "back converting xml\n";
    `$start /Users/james/svnworkspaces/VoxPortSupport/slicer-to-avizo.pl < ${ln}.txt > ${ln}_hf.atlas.xml`;

}
