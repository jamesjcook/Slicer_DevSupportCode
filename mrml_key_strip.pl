#!/usr/bin/perl
# mrml_key_strip.pl
# eliminate keys we dont want in our mrml file.
# takes inmrml could specifiy outmrml as well

use strict;
use warnings;

my $ERROR_EXIT = 1;
my $GOOD_EXIT  = 0;
use Env qw(RADISH_PERL_LIB RADISH_RECON_DIR WORKSTATION_HOME WKS_SETTINGS RECON_HOSTNAME WORKSTATION_HOSTNAME); # root of radish pipeline folders
if (! defined($RADISH_PERL_LIB)) {
    print STDERR "Cannot find good perl directories, quiting\n";
    exit $ERROR_EXIT;
}
# if (! defined($RADISH_RECON_DIR) && ! defined ($WORKSTATION_HOME)) {
#     print STDERR "Environment variable RADISH_RECON_DIR must be set. Are you user omega?\n";
#     print STDERR "   CIVM HINT setenv RADISH_RECON_DIR /recon_home/script/dir_radish\n";
#     print STDERR "Bye.\n";
#     exit $ERROR_EXIT;
# }
# if (! defined($RECON_HOSTNAME) && ! defined($WORKSTATION_HOSTNAME)) {
#     print STDERR "Environment variable RECON_HOSTNAME or WORKSTATION_HOSTNAME must be set.";
#     exit $ERROR_EXIT;
# }

use lib split(':',$RADISH_PERL_LIB);
require Headfile;
#require hoaoa;
#import hoaoa qw(aoa_hash_to_headfile);
#use hoaoa qw(aoa_hash_to_headfile display_header display_complex_data_structure);
#require shared;
require pipeline_utilities;
use civm_simple_util qw(load_file_to_array write_array_to_file get_engine_constants_path printd whoami whowasi debugloc sleep_with_countdown $debug_val $debug_locator);# debug_val debug_locator);di

use Data::Dump qw(dump);



my $inmrml=$ARGV[0];
#my $inpath=$ARGV[1];
my $rename_type=$ARGV[1];
#my $color_table_out="";
my $outmrml=$ARGV[2];
my $outmrml_n;
#my @color_table;
if ( ! defined $inmrml ) { 
    print("ERROR: no mrml specified");
    exit;
}
if ( ! defined $rename_type ) { 
    $rename_type='modelfile';
}
{
    my ($p,$n,$e)=fileparts($inmrml,2);
    if ($rename_type eq 'clean' ) { 
	$outmrml_n=$p.$n."_template".$e;
	$outmrml=$p.$n."_mhn".$e  if ( ! defined $outmrml ) ;
    } else {
	$outmrml_n=$p.$n."_template".$e ;
	$outmrml=$p.$n."_$rename_type".$e if ( ! defined $outmrml ) ;
    }
    
    print("Auto mrml out will be \"$outmrml\".\n") if ( ! defined $outmrml ) ;
}

#load_file_to_array($inpath,\@color_table);
my ($xml_data,$xml_parser)=xml_read($inmrml,'giveparser');
#{
#    my ($n,$p,$e)=fileparts($inpath);
#     $color_table_out=$p.$n."_$rename_type".$e;
#}
# these are our fibebundle nodes as noted in slicer
#vtkMRMLFiberBundleNode
#vtkMRMLFiberBundleTubeDisplayNode
#vtkMRMLFiberBundleLineDisplayNode
#vtkMRMLFiberBundleGlyphDisplayNode
#vtkMRMLLinearTransformNode


# Fiber bundle expansion didnt quite work.
# Defacto setup with a clean settings file, no tracts show up. There is a loading glitch in that instance(maybe missing extensions?)
# After manually using correct settings, tube display is on by default.
# Maybe deleting those nodes will address that, howver its not clear that is the right answer.
# 

my @node_types_preserved=qw(MRML LinearTransform TransformStorage Version UserTags SubjectHierarchy SubjectHierarchyItem);
my @model_node_types=qw(ModelHierarchy ModelDisplay Model ModelStorage );
my @fiber_node_types=qw(FiberBundle DiffusionTensorDisplayProperties FiberBundleTubeDisplayNode FiberBundleLineDisplayNode FiberBundleGlyphDisplayNode);
push(@node_types_preserved,@model_node_types);
push(@node_types_preserved,@fiber_node_types);
#print("colortable ".($#color_table+1)." lines loaded\n");
mrml_clear_nodes($xml_data,@node_types_preserved);
mrml_to_file($xml_data,'  ',0,'pretty','',$outmrml);

# not sure the purpo
if( $rename_type eq 'modelfile' || $rename_type eq 'ontology' || $rename_type eq 'abrev') {
#    mrml_clear_nodes($xml_data,("ModelHierarchy","ModelDisplay","Version", "UserTags"));
#    mrml_to_file($xml_data,'  ',0,'pretty','',$outmrm_n);
}
