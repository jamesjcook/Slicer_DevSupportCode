#!/usr/bin/perl
# mrml_color_update.pl
# takes inmrml, and incolor table, could specifiy outmrml as well
# changes the mrml color to the value in the color table. 

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
use text_sheet_utils;
use Data::Dump qw(dump);
$debug_val=45;


my $inmrml=$ARGV[0];
my $p_color_table_in=$ARGV[1];
#my $color_table_out="";
my $outmrml=$ARGV[2];

#my @color_table;
if ( ! defined $inmrml ) { 
    print("ERROR: no mrml specified");
    exit;
}
my ($p,$n,$e)=fileparts($inmrml,2);
#if ( ! defined $outmrml ) {
$outmrml=$p.$n."_color_update".$e; 
print("Auto mrml out will be \"$outmrml\".\n");
#}


my ($xml_data,$xml_parser)=xml_read($inmrml,'giveparser');

my $header={};
$header->{"Value"}=0;
$header->{"Name"}=1;
$header->{"c_R"}=2;
$header->{"c_G"}=3;
$header->{"c_B"}=4;
$header->{"c_A"}=5;

my $splitter={};#
### This splitter Regex is for the alex badea style color tables.
# need a new/different one for anything else.
$splitter->{"Regex"}='^_?(.+?)(?:___?(.*))$';# taking this regex
#$splitter->{"Regex"}='^.*$';# taking this regex
$splitter->{"Input"}=[qw(Name Structure)];# reformulate structure column, keeping original in name
$splitter->{"Output"}=[qw(Abbrev Name)];  # generating these two
### This splitter Regex is for plain comma separated lists.

$header->{"Splitter"}=$splitter;
$header->{"LineFormat"}='^#.*';
$header->{"Separator"}=" ";

my $c_table=text_sheet_utils::loader($p_color_table_in,$header);
#Data::Dump::dump($c_table);
my $model_prefix="Model_";
# get models
my @mrml_nodes=mrml_find_by_id($xml_data->{"MRML"},".*","Model");
#dump(@mrml_nodes);
# This first regex works for plain model names which are the same as color table names.
$splitter->{"Regex"}="^$model_prefix([0-9]+)_".'(_*(.*))?$';
#$splitter->{"Regex"}="^$model_prefix([0-9]+)_".'(_?(.+?)(?:___?(.*))?)$';# taking this regex, which is good for the RBSC, didnt work for the mouse!
#$splitter->{"Regex"}="^($model_prefix([0-9]+)_".'_.+?_(.*))$';# taking this regex, which is good for the RBSC, didnt work for the mouse!
$splitter->{"Output"}=[qw(Structure Value Name)];  # generating these three
my @missing_model_messages;
# for each model get display
foreach my $mrml_model (@mrml_nodes) {
    my $mrml_name=$mrml_model->{"name"};
    my @field_keys=@{$splitter->{"Output"}};# get the count of expected elementes
    my @field_temp = $mrml_name  =~ /$splitter->{"Regex"}/x;
    #print("$mrml_name\n");
    my $msg="";
    if ( scalar(@field_keys) != scalar(@field_temp) ) {
	$msg=sprintf("Model input name entry seems incomplele or badly formed.($mrml_name)");
	while( ( $#field_temp<$#field_keys ) && ( length($mrml_name)>0) ) {
	    push(@field_temp, $mrml_name);
	}
	#dump(@field_temp);next;
    }
    #dump(@field_temp);
    my %n_a;
    if ( scalar(@field_keys) == scalar(@field_temp) ) {
	@n_a{@field_keys} = @field_temp;
	if (length($msg)>0){
	    print($msg." But we've fudged it.\n");next;}
	
    } else {
	warn($msg." and couldnt recover. expected".scalar(@field_keys).", but we got ".scalar(@field_temp));
	dump(@field_keys,@field_temp);
	next;
    }
    
    ### 
    # get the color_table info by value, name, abbrev, or structure
    ###
    # we sort throught the possible standard places it could be.
    # adding second chance via color lookup.
    my $c_entry;
    my @c_test=qw(Value Name Abbrev Structure); # sets the test order, instead of just using the collection order of splitter->{'Output'}.
    my $tx;
    do {
	$tx=shift(@c_test) ;
    } while(defined $n_a{$tx} 
	    && ! exists ($c_table->{$tx}->{$n_a{$tx}} )
	    && $#c_test>0 );
    
    if( exists($n_a{$tx}) 
	&& exists($c_table->{$tx}->{$n_a{$tx}}) ) {
	$c_entry=$c_table->{$tx}->{$n_a{$tx}};
    } else {
	print("$mrml_name\n\tERROR, No color table Entry found!\n");
	push(@missing_model_messages,"No color table entry".$mrml_name);
	#dump(%n_a);
    }
    if( defined $c_entry) {
	print("\tGot new color\n");
    }else {
	die("NO COLOR AVAILABLE");}
    my @vtkMRMLModelDisplayNodes;
    if ( exists ($mrml_model->{"displayNodeRef"} ) ) {
	@vtkMRMLModelDisplayNodes=mrml_attr_search( $xml_data,"id",'^'.$mrml_model->{"displayNodeRef"}.'$',"ModelDisplay");# this may not be what i'm looking to do.`
     #} elsif ( exists ($parent_ref->{"displayNodeID"} ) ) {
     # @vtkMRMLModelDisplayNodes=mrml_attr_search( $xml_data,"id",$parent_ref->{"displayNodeID"}.'$',"ModelDisplay");    # this gets the root hierarchy node's modeldisplaynode.
    # warn("WARN: Using root display node for template.");
	
    } else {
	next;
	warn("WARN: Had to just grab the first ModelDisplay due to missing root");
	# if we dont have a parent node, then just get the first one, hope its the right thing.
	@vtkMRMLModelDisplayNodes=mrml_find_by_id($xml_data,$mrml_nodes[0]->{"displayNodeRef"}."\$"); 
	if ( scalar(@vtkMRMLModelDisplayNodes) == 0 || ! keys %{$vtkMRMLModelDisplayNodes[0]} ){
	    #dump($parent_ref);
	    #die "Parent ref problem";
	}
    }
    #my @model_color=split(" ",$vtkMRMLModelDisplayNodes[0]->{"color"});
    #print("there are ".scalar(@vtkMRMLModelDisplayNodes)." found for this ref:".$mrml_model->{"displayNodeRef"}."\n");
    for(my $dn=0;$dn<=$#vtkMRMLModelDisplayNodes;$dn++){
	#print("setting color on ".($dn+1)."\n");
	$vtkMRMLModelDisplayNodes[$dn]->{"color"}=sprintf("%f %f %f",
							  $c_entry->{"c_R"}/255,$c_entry->{"c_G"}/255,$c_entry->{"c_B"}/255);
    }
    
    
#   set display color to ctable entry
}
dump(sort(@missing_model_messages));
#mrml_clear_nodes($xml_data,("ModelHierarchy","ModelDisplay","Model","ModelStorage","Version", "UserTags"));
#mrml_clear_nodes($xml_data,("ModelHierarchy","ModelDisplay","Version", "UserTags"));
mrml_to_file($xml_data,'  ',0,'pretty','',$outmrml);
