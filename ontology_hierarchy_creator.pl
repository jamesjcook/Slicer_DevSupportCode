#!/usr/bin/perl
# ontology tab sheet converter.pl
# used to rename structures in slicer MRML file to their complete ontology name or to their Abbreviation.
# uses the ontology tab sheet to generate "safe" filenames, and assumes the structures are named that in the mrml file.
# checks the hard coded label look up table to make sure the name listed there matches the name in MRML file. 
# 
# loads tab sheet and operates over every line of that file. 
#   renames modelhierarchynodes to the name of interest as it goes.
#   creates a full hierarchy hash as it goes, attaches structure to highest level element.
#   checks the lookuptable mentioned for the correct entry, and replaces incorrect ones. Does not check vtk filename.
#
# saves updated mrml to mrml_mrh.
# clears nodes besides the modelhierarchy and dispaly, then saves mrml as mrml_template.
#
# TODO 
# for tractograyphdisplay, some intelligent way, copy 3n_l settings to other tratography nodes. (specifically copy percentage display, and color by segment.)
# lets make tractography repair a second file. 


use strict;
use warnings;
use Data::Dump qw(dump);
use Clone qw(clone);
use Getopt::Std;# qw(getopts);
use File::Basename;
#use String::Util qw(trim); $branch_name=trim($branch_name)
use Text::Trim qw(trim);
use List::MoreUtils qw(uniq);
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
#use xml_read qw(xml_read);
our %opt;
if (! getopts('d:c:g:h:m:o:t:', \%opt||$#ARGV>=0)) {
    # (d)ebug (c)olor_table (h)ierarchy (m)rml_in (o)utput (t)ype_of_renaming
    die "$!: Option error, valid options, -h hierarchy.csv -m input_mrml.mrml -c colortable.txt (-o output.mrml)? (-t (Clean|Name|Structure|Abbrev))?";
}
#-h hierarchy.csv
#-m inmrml.mrml
#-c colortabl.txt
#-o output.mrml

### What about different column names for the same things? Should that be supported, or should we just bludgeon things here.
#my $shorthand="Abbrev"
#Abbreviation

#my $ontology_inpath=$ARGV[0];
my $p_ontology_in=$opt{"h"};# ontology path in
my $p_ontology_out=$opt{"g"} if exists($opt{"g"}); #ontolgy path out
#my $p_mrml_in=$ARGV[1];   
my $p_mrml_in=$opt{"m"};    # mrml path in 
#my $p_mrml_out=$ARGV[2];   # mrml path out
my $p_mrml_out=$opt{"o"};
#my $rename_type=$ARGV[3];
my $rename_type=$opt{"t"};  
my $p_color_table_in=$opt{"c"};#color table out
my $model_prefix="Model_";
$debug_val=20;
if ( exists $opt{d}) {
    $debug_val=$opt{d};
}

my $p_mrml_out_template;
if ( ! defined $p_mrml_in || ! defined $p_color_table_in || ! defined $p_ontology_in ) { 
    print("specifiy at least:\n\t(-h hierarchical_ontology)\n\t(-m mrml)\n\t(-c color_table).\nOptionally specify\n\t(-o output mrml)\n\t(-t  rename type [Clean|Name|Structure|Abbrev])\n");
    if ( ! defined $p_ontology_in  ) {
    	print ("ERROR: no ontology specified\n"); }
    if ( ! defined $p_mrml_in ) {
	print ("ERROR: no mrml specified\n"); }
    if ( ! defined $p_color_table_in ) {
    	print ("ERROR: no color_table specified\n"); } 
    exit;
}
if ( ! defined $rename_type ) { 
    $rename_type='Structure';
}
if ( $rename_type !~/(Clean|Name|Structure|Abbrev)/x ) {
    die "Rename type $rename_type not in (Clean|Name|Structure|Abbrev)";
}
if ( ! defined $p_mrml_out ) {
    my ($p,$n,$e)=fileparts($p_mrml_in,3);
    #print "n=$n p=$p e=$e\n";
    $p_mrml_out=$p.$n."_".$rename_type."_out".$e;
    print("Auto mrml out will be \"$p_mrml_out\".\n") ;
}

my ($Tp,$Tn,$Te)=fileparts($p_color_table_in,3);
my $p_color_table_out=$Tp.$Tn."_".$rename_type."_out".$Te;

if ( ! exists($opt{"g"}) ) {
    ($Tp,$Tn,$Te)=fileparts($p_ontology_in,3);
} else {
    ($Tp,$Tn,$Te)=fileparts($p_ontology_out,3);
}
$p_ontology_out=$Tp.$Tn."_".$rename_type."_out".$Te;
my $p_ontology_structures_out=$Tp.$Tn."_".$rename_type."_Lists_out".$Te;
my $p_ontology_levels_out=$Tp.$Tn."_".$rename_type."_Levels_out".$Te;
my $p_ontology_assignment_out=$Tp.$Tn."_".$rename_type."_assignment_out".$Te;
my $p_ontology_structures_out_hf=$Tp.$Tn."_".$rename_type."_Lists_out.headfile";
print "MRML = $p_mrml_in -> $p_mrml_out\n";
print "Color = $p_color_table_in -> $p_color_table_out\n";
print "Hierarchy = $p_ontology_in -> $p_ontology_out\n";
#exit;
###
# color_table parse.
###
# turn into useful data lookup structures.
# colortable we can rely on v and rgba and the name being the structure name in the mrmrl.
# how about a rgba lookup, and a structure lookup hash. hmmm! rgba might not be unique!!!! its just a secondary indicator!
# so, structure to value, rgba,
# and name to value, rgba,
# and Abbrev to value, rgba.
# should these be hashes of 5 element arrarys?

# VALUE NAME RED GREEN BLUE ALPHA
my $header={};
#$header->{"Structure"}=-1;
#$header->{"Abbrev"}=-1;
$header->{"Value"}=0;
$header->{"Name"}=1;
$header->{"c_R"}=2;
$header->{"c_G"}=3;
$header->{"c_B"}=4;
$header->{"c_A"}=5;

my $splitter={};#
# a aplitter to split a field into alternat parts. 
#	my ($c_Abbrev,$c_name)= $tt_entry[1] =~/^_?(.+?)(?:___?(.*))$/;


### This splitter Regex is for the alex badea style color tables.
# need a new/different one for anything else.
$splitter->{"Regex"}='^_?(.+?)(?:___?(.*))$';# taking this regex
#$splitter->{"Regex"}='^.*$';# taking this regex
$splitter->{"Input"}=[qw(Name Structure)];# reformulate structure column, keeping original in name
$splitter->{"Output"}=[qw(Abbrev Name)];  # generating these two
### This splitter Regex is for plain comma separated lists.

#### EXAMPLE OF FIRST LETTER OF EACH STR
###perl -wMstrict -le
###my $str = 'eternal corruption defilement';
###$str =~ s{ \b ([[:alpha:]]) [[:lower:]]* \s* }{\U$1}xmsg;
###print qq{'$str'};
#$splitter->{"Regex"}='s{ \b ([[:alpha:]])_?[[:lower:]]* \s* }{$1}xmsg';# taking this regex
#$splitter->{"Regex"}='^((.+))$';# taking this regex, alternate for take all  $splitter->{"Regex"}='^.*$';
#$splitter->{"Input"}=[qw(Structure Name)];# reformulate this var, keeping original in other
#$splitter->{"Output"}=[qw(Name Abbrev )];  # generating these two

#1 Cingulate_Cortex_Area_24a 255 0 0 255


$header->{"Splitter"}=$splitter;
$header->{"LineFormat"}='^#.*';
$header->{"Separator"}=" ";


my $c_table=text_sheet_utils::loader($p_color_table_in,$header);
#dump($c_table);

### BIG PILE OF DEBUG PRINTS CONTROLELD BY THIS TRIPLICATE VARIABLE, TURN ANY ON TO DUMP SPECIFIED CONTENTS AND STOP.
my ($d_abr,$d_nam,$d_str,$d_line)=(0,0,0,0);
my $Tr;
if ($d_abr){
    print STDERR ("Dump color:abbrev\n");
    $Tr=$c_table->{"Abbrev"};
    dump($Tr);
}
if ($d_nam){
    print STDERR ("Dump color:name\n");
    $Tr=$c_table->{"Name"};
    dump($Tr);
}
if ($d_str){
    print STDERR ("Dump color:structure\n");
    $Tr=$c_table->{"Structure"};
    dump($Tr);
}
if ($d_line){
    print STDERR ("Dump color:structure\n");
    $Tr=$c_table->{"t_line"};
    dump($Tr);
}
if ($d_abr||$d_nam||$d_str||$d_line){
    $Tr=$c_table->{"t_line"};
    printf("%i\n",scalar(keys %{$c_table->{"t_line"}}));
    printf("%i\n",scalar(keys %$c_table));
    exit;
}
	#
#my $parser=xml_read($p_mrml_in);
#my $mrml_data=xml_read($p_mrml_in);
    #print("THE END\n");exit;
if  ($d_abr||$d_nam||$d_str){
    exit;}

my ($mrml_data,$xml_parser)=xml_read($p_mrml_in,'giveparser');

if(0){
    dump($xml_parser);
}
if(0){
    dump($mrml_data);
}


###
# Process ontology CSV file.
###
# determine the different file names and paths per each convention.
# move files into appropriate destination place, from starting place/places.

$splitter->{"Regex"}='^_?(.+?)(?:___?(.*))$';# taking this regex
#$splitter->{"Regex"}='^.*$';# taking this regex
$splitter->{"Input"}=[qw(Structure Structure)];# reformulate this var, keeping original in other


$splitter->{"Output"}=[qw(Abbrev Name)];  # generating these two
#### EXAMPLE OF FIRST LETTER OF EACH STR
###perl -wMstrict -le
###my $str = 'eternal corruption defilement';
###$str =~ s{ \b ([[:alpha:]]) [[:lower:]]* \s* }{\U$1}xmsg;
###print qq{'$str'};
###$splitter->{"Regex"}='s{ \b ([[:alpha:]])_?[[:lower:]]* \s* }{$1}xmsg';# taking this regex
#$splitter->{"Regex"}='^((.+))$';# taking this regex    $splitter->{"Regex"}='^.*$';# taking this regex
#$splitter->{"Input"}=[qw(Structure Name)];# reformulate this var, keeping original in other
#$splitter->{"Output"}=[qw(Name Abbrev )];  # generating these two

my $h_info={};
$h_info->{"Splitter"}=$splitter;
$header->{"LineFormat"}='^#.*';
#$header->{"Separator"}=" ";# for the ontology, we let it auto find the separator in the loader.
my $o_table=text_sheet_utils::loader($p_ontology_in,$h_info);
#dump( $o_table);
#exit;



my $ontology;
my $null;
#$ontology=cleanup_ontology_levels($o_table,$c_table); # we pass the color table, but it doesnt look like we use it, testing passinga null var shows the code still runs. 
$ontology=cleanup_ontology_levels($o_table,$null);

if ( 0 ) {
dump(%{$ontology->{"Hierarchy"}});
dump(%{$ontology->{"Branches"}});
dump(%{$ontology->{"Twigs"}});
dump(%{$ontology->{"SuperCount"}});
dump(%{$ontology->{"SuperLevel"}});
dump(%{$ontology->{"order_lookup"}});

exit;


}
# if (keys %{ $ontology } ) {
#     print ("YES-keys\n");
# }
# if (! keys %{ $ontology } ) {
#     print ("NO-keys\n");
# }
#exit;   
####
# New method, we have our text spreadsheets loaded.
####
# we should look at each model from the xml, these should all have an entry in the color table.
# Lets dump some summary data of where we are so far.
use List::Util qw(first max maxstr min minstr reduce shuffle sum);
my ( $c_count, $o_count )= (0,0);

if ( 1 ) { # take advantage of always having the t_line field, and its guarenteed unique. 
    $c_count=scalar(keys %{$c_table->{"t_line"}});
    $o_count=scalar(keys %{$o_table->{"t_line"}});
} else {
    foreach (keys %$c_table){
	$c_count=max((scalar(keys %{$c_table->{$_}})),$c_count );
    }
    foreach (keys %$o_table){
	$o_count=max((scalar(keys %{$o_table->{$_}})),$o_count );
    }
}
my $ONTOLOGY_INSERTION_LINE=$o_count;# next insertion point.
while ( exists($o_table->{"t_line"}->{$ONTOLOGY_INSERTION_LINE}) ){
    $ONTOLOGY_INSERTION_LINE++;
}
printf("Final ontology line number =".($ONTOLOGY_INSERTION_LINE-1)."\n");
my $COLOR_TABLE_INSERTION_LINE=$c_count;# next insertion point.
while ( exists($o_table->{"t_line"}->{$COLOR_TABLE_INSERTION_LINE}) ){
    $COLOR_TABLE_INSERTION_LINE++;
}
printf("Final color_table line number =".($COLOR_TABLE_INSERTION_LINE-1)."\n");
#my $c_count=(scalar(keys %{$c_table->{"Structure"}}));# simple counts
#my $o_count=(scalar(keys %{$o_table->{"Structure"}})); # simple counts
print("color_table ".$c_count." lines loaded\n");
print("ontology ".$o_count." lines loaded\n");
if ($o_count!=$c_count) {
    warn("uneven color_table to ontology count.");
}
print("\n\n");

my $rootHierarchyNodeID="vtkMRMLModelHierarchyNode";#vtkMRMLModelHierarchyNode1 #vtkMRMLHierarchyNode1"
my $rootHierarchyNode={};
{
    $rootHierarchyNode=$mrml_data->{"MRML"}->{"ModelHierarchy"}[0]; # first modelhierarchy node
    #$rootHierarchyNode=$mrml_data->{"MRML"}->{"ModelHierarchy"}[$#{$mrml_data->{"MRML"}->{"ModelHierarchy"}}]; # last modelhierarchy node
    # while the current root has a parent, its not really the root... so we should get its parent.
    while (exists ($rootHierarchyNode->{"parentNodeRef"}) ) {
	print("Looking up ".$rootHierarchyNode->{"parentNodeRef"}."\n");
	# using exact find.
    	my @parent_candidates=mrml_find_by_id($mrml_data,'^'.$rootHierarchyNode->{"parentNodeRef"}.'$',"ModelHierarchy");
	while (scalar(@parent_candidates) && ! keys %{ $parent_candidates[0]} ) {
	    shift(@parent_candidates);
	}
	if (scalar(@parent_candidates) && keys %{ $parent_candidates[0]} ) {
	    $rootHierarchyNode=$parent_candidates[0];
	} else {
	    print("EMPTYNODE\n");
	}
	if (!scalar(@parent_candidates) ){
	    die("PARENTLOOKUPFAILURE");
	}
    }
    if ( ! defined $rootHierarchyNode->{"id"} ) {
	die("Couldnt find node");
    } else {
	print("root is ".$rootHierarchyNode->{"id"}."\n");
    }
    $rootHierarchyNodeID=$rootHierarchyNode->{"id"};
}
if (! keys %{ $rootHierarchyNode} ) {
    print("Root Node EMPTY!!!");
    exit;
}
#dump($rootHierarchyNode);
#exit;
#my $mrml_data=mrml_find_by_name($mrml_data->{"MRML"},"whiteSPCmatter","ModelHierarchy");
#my $mrml_data=mrml_find_by_name($mrml_data,"whiteSPCmatter","ModelHierarchy");
#my $mrml_data=mrml_find_by_name($mrml_data,"whiteSPCmatter");#,"ModelHierarchy");
#display_complex_data_structure($mrml_data,'  ');
#display_complex_data_structure(\@refs,'  ')

my @mrml_nodes_loaded=mrml_find_by_id($mrml_data,".*"); # could i just scalar that for how i'm doing things?
print("mrml ".(scalar(@mrml_nodes_loaded))." nodes loaded.\n");
#
#my @mrml_nodes=mrml_find_by_name($mrml_data->{"MRML"}->{"SceneView"},".*","Model");
#my @mrml_nodes=mrml_find_by_name($mrml_data->{"MRML"},".*","Model");
my @mrml_nodes=mrml_find_by_id($mrml_data->{"MRML"},".*","Model");
print("\tModel's:".(scalar(@mrml_nodes))."\n");

###
# set up the name splitter for the slicer model output names
###
# grouping of the regex is what determines the output. Output MUST be specified in the order splitte->{'Regex'} will return.
$splitter->{"Regex"}="^$model_prefix([0-9]+)_".'(_?(.+?)(?:___?(.*))?)$';# taking this regex, which is good for the RBSC, didnt work for the mouse!
#$splitter->{"Regex"}="^$model_prefix([0-9]+)_".'(_?(.+?)(?:___?(.*))?)$';# taking this regex
#$splitter->{"Regex"}='^.*$';# taking this regex
#$splitter->{"Regex"}="^$model_prefix([0-9]+)_".'(_?(.*?)(?:___?(.+))?)$';# taking this regex, which is good for the RBSC, didnt work for the mouse!
# HUMAN BRAINSTEM SPLITTER FAILURE!!!!.
$splitter->{"Regex"}="^($model_prefix([0-9]+)_".'_.+?_(.*))$';# taking this regex, which is good for the RBSC, didnt work for the mouse!
#Model_5__5_Fouth_ventricle.vtk
# this is the splitter input pre 201802 revision
#$splitter->{"Input"}=[qw(Structure Structure)];# reformulate this var, keeping original in other
#$splitter->{"Input"}=[qw(  )];# reformulate structure var, keeping original in Model
# this is the splitter output pre 201802 revision
#$splitter->{"Output"}=[qw(Value Structure Abbrev Name)];  # generating these four
$splitter->{"Output"}=[qw(Structure Value Name)];  # generating these three

###
#foreach model in mrml_data
###
my @missing_model_messages;
my @found_via_ontology_color;
my $processed_nodes=0;
my $do_unsafe=0;
my %l_1;
my %onto_hash;
print("---\n");
print("\tBegin model processing!\n");
print("---\n\n\n");
foreach my $mrml_model (@mrml_nodes) {
    # Names come from color_tables, so the names should follow a regular pattern here + the added slicer model gen bits.
    my %n_a; # a holder for the multiple lookup possibilities for each model. 
    # This is a multiple level hash cross ref of the names and all the values. 
    # model names are split into the component parts, given the splitter defined above.
    # The default splitter used for paxinos/alex(RBSC)'s labels shows lookup potentials of:
    #     value, structure_full_avizo_name, Abbrev, Name.
    # ex. modelname Model_1_ABC__A_big_name_completely  becomes
    # value=1, structure_full_avizo_name=ABC__A_big_name_completely, Abbrev=ABC, Name=A_big_name_completely.
    my $mrml_name=$mrml_model->{"name"};
    my @field_keys=@{$splitter->{"Output"}};# get the count of expected elementes
    my @field_temp = $mrml_name  =~ /$splitter->{"Regex"}/x;
    my $msg="";
    if ( scalar(@field_keys) != scalar(@field_temp) ) {
	$msg=sprintf("Model input name entry seems incomplele or badly formed.($mrml_name)");
	while( ( $#field_temp<$#field_keys ) && ( length($mrml_name)>0) ) {
	    push(@field_temp, $mrml_name);
	}
    }
    
    if ( scalar(@field_keys) == scalar(@field_temp) ) {
	@n_a{@field_keys} = @field_temp;
	if (length($msg)>0){
	    print($msg." But we've fudged it.\n");}
    } else {
	warn($msg." and couldnt recover. expected".scalar(@field_keys).", but we got ".scalar(@field_temp));
	dump(@field_keys,@field_temp);
	next;
    }
    #dump(\%n_a);die;
    if ( $n_a{"Value"}==0 ){ # this throws an error becuase it may not be numeric... but it works anyway.
	dump(%n_a);
	print("Special exception for value 0\n");
	next;
    }
    
    #### NEED TO ENSURE THE n_a HASH IS CORRECT HERE.
    # theoritically we've run the cleanup function ensuring the ontology is correct.
    #
    # For poorly formed entries we can have unfilled or missing fields!
    #
    # n_a only has Value as a trustworty field.
    if(! exists($n_a{"Name"}) && exists($n_a{"Abbrev"}) ){
	$n_a{"Name"}=$n_a{"Abbrev"};
    }
    if(exists($n_a{"Name"}) && ! exists($n_a{"Abbrev"}) ){
	$n_a{"Abbrev"}=$n_a{"Name"};
    }
    if(!exists($n_a{"Name"})
       || ! exists($n_a{"Value"})
       || ! exists($n_a{"Abbrev"})
       || ! exists($n_a{"Structure"}) ){
	warn("Critical falure for model $mrml_name skipping...\n");
	dump(%n_a);
	sleep_with_countdown(15);
	next;	
    }
    ### 
    # get the color_table info by value, name, abbrev, or structure
    ###
    # we sort throught the possible standard places it could be.
    # adding second chance via color lookup.
    my ($c_entry,$o_entry);
    my @c_test=qw(Value Name Abbrev Structure); # sets the test order, instead of just using the collection order of splitter->{'Output'}.
    my $tx;
    do {
	$tx=shift(@c_test) ;
    } while(defined $n_a{$tx} 
	    && ! exists ($c_table->{$tx}->{$n_a{$tx}} )
	    && $#c_test>0 );
    
    if( exists($n_a{$tx}) && exists($c_table->{$tx}->{$n_a{$tx}}) ) {
	$c_entry=$c_table->{$tx}->{$n_a{$tx}};
    } else {
	print("$mrml_name\n\tERROR, No color table Entry found!\n");
	push(@missing_model_messages,"No color table entry".$mrml_name);
	#dump(%n_a);
    }
    ### 
    # get the ontology_table info by abbrev, or value, or Name
    ###
    # we sort throught the possible standard places it could be.
    # adding second chance via color lookup.
    my @o_test=qw(Name Abbrev Structure Value);  # sets the test order, instead of just using the collection order of splitter->{'Output'}.
    do {
	$tx=shift(@o_test) ;
    } while(defined $n_a{$tx} 
	    && ! exists ($o_table->{$tx}->{$n_a{$tx}} )
	    && $#o_test>0 );
    if( exists($n_a{$tx}) && exists($o_table->{$tx}->{$n_a{$tx}}) ) {
	$o_entry=$o_table->{$tx}->{$n_a{$tx}};
    } else {
	print("$mrml_name\n\tERROR, No ontology Entry found!\n");
	if ( 1 ) {
	    push(@missing_model_messages,"No ontology table entry: ".$mrml_name);
	    #dump(%n_a);
	} else {
	    #### Harder try to find the ontology using the colors.
	    if ( not defined($o_entry) ) {
		print("no ontology entry yet, trying color!\n");
		@o_test=qw(c_R c_G c_B );#c_A);
		my @found_parts;
		foreach (@o_test){
		    if ( exists ($o_table->{$_}->{$c_entry->{$_}})  ) {
			print("\t got $_\n");
			push(@found_parts,$_);
		    }
		}
		if( scalar(@o_test) == scalar(@found_parts) ) {
		    # there's a chance!
		    print("We found enough color parts! We can dive in !\n");
		    sleep_with_countdown(5);
		    my $o_entry=$o_table;
		    foreach (@o_test){
			if ( exists($o_entry->{$_}->{$c_entry->{$_}}) ){
			    print("Going deeper with $c_entry->{$_}\t");
			    $o_entry=$o_table->{$_};
			}
		    }
		}
	    }
	    if( not defined $o_entry) {
		print("$mrml_name\n\tERROR, No ontology Entry found!\n");
		push(@missing_model_messages,"No ontology table entry: ".$mrml_name);
		dump(%n_a);	
	    }
	}
    }
    #
    # if we failed to find one of the entries, dump the info here.
    #
    if ( not defined($o_entry) || not defined ($c_entry) ) {
	warn("Model $mrml_name missing ontology or color entries");
	if ( ! defined($o_entry) && ! defined($c_entry) ) {
	    warn("INVENTING INFORMATION for ".$mrml_name);
	    $c_entry=\%{clone %n_a};
	    $c_entry->{"t_line"}=$COLOR_TABLE_INSERTION_LINE;
	    {
		my @c_vals=qw(c_R c_G c_B);
		#my @c_vals=qw(c_R c_G c_B);
		@{$c_entry}{@c_vals}=(255) x scalar(@c_vals);
		$c_entry->{"c_A"}=0;
	    }
	    my @c_columns=qw(Value Name Abbrev Structure t_line);
	    for my $col (@c_columns) {
		if ( ! exists($c_table->{$col}->{$c_entry->{$col}} ) ) {
		    $c_table->{$col}->{$c_entry->{$col}}=$c_entry;
		    printf("Added c_entry to index $col at $c_entry->{$col}\n");
		} else {
		    die("$col has entry for $c_entry->{$col}\n" ) ;
		}
		if ( ! exists($c_table->{$col}) ){ 
		    die("c_table missing Index: $col\n");
		}
	    }
	}
	if ( ! defined($o_entry) && defined($c_entry) ) {
	    print("FOUND C_ENTRY MISSING O_ENTRY\n") if $debug_val>=35;
	    dump($c_entry) if $debug_val >= 35;
	    # ADD the o_entry to the o_table here!!!
	    # Hash_dupe!
	    # structure abbrev level_1 .. level_n c_r c_g c_b c_a
	    #	    $o_entry=
	    $o_entry=\%{clone $c_entry};
	    $o_entry->{"Level_1"}="UNSORTED";# they're all unsorted : )
	    $o_entry->{"DirectAssignment"}=["UNSORTED"];# they're all unsorted : )
	    $o_entry->{"t_line"}=$ONTOLOGY_INSERTION_LINE;
	    $ONTOLOGY_INSERTION_LINE++;
	    #@$o_entry{keys %$c_entry}=$c_entry->{keys %$c_entry};
	    # now for each key in the o_table add a 0 to our o_entry, THEN add our o_entry to each point of the o_table.
	    my @o_columns;
	    if ( 1 )  {
		@o_columns=qw(Name Abbrev Structure t_line);
	    } elsif ( 0 ) {
		@o_columns=keys(%{$o_entry});
	    } else {
		@o_columns=keys %{$o_table->{'Header'}};#keys %$o_table;
		foreach (@o_columns) {
		    if ( ! exists($o_entry->{$_} ) ) {
			$o_entry->{$_}=0;
		    }
		}	    
	    }
	    # for each column update the ontology.
	    for my $col (@o_columns) {
	    #my $col="t_line"; {
		if ( ! exists($o_table->{$col}->{$o_entry->{$col}} ) ) {
		    $o_table->{$col}->{$o_entry->{$col}}=$o_entry;
		    printf("Added o_entry to index $col at $o_entry->{$col}\n");
		    #sleep_with_countdown(2);
		} else {
		    die("$col has entry for $o_entry->{$col}");
		}
		if ( ! exists($o_table->{$col}) ){ 
		    die("o_table missing Index: $col\n");
		}
	    }
	    #dump($o_entry);
	}
 	if ( defined($o_entry) && ! defined($c_entry) ) {
	    print("FOUND O_ENTRY MISSING C_ENTRY\n") if $debug_val>=35;
	    dump($o_entry) if $debug_val>=35;
	    # ADD the c_entry to the c_table here!!!
	    $c_entry=\%{clone $o_entry};
	    my @c_columns=qw(Value Name Abbrev Structure t_line);
	    for my $col (@c_columns) {
	    #my $col="t_line"; {
		if ( ! exists($c_table->{$col}->{$c_entry->{$col}} ) ) {
		    $c_table->{$col}->{$c_entry->{$col}}=$c_entry;
		    printf("Added c_entry to index $col at $c_entry->{$col}\n");
		    #sleep_with_countdown(2);
		} else {
		    die("$col has entry for $c_entry->{$col}\n" ) ;
		}
		if ( ! exists($c_table->{$col}) ){ 
		    die("c_table missing Index: $col\n");
		}
	    }
	}
	#next;
    } else {
	#dump($c_entry);
    }
    #next;
    ##TODO
    # now that we've found our ontolgoy and color table entries Combine that info in all three data locations.
    # n_a has these fields Value Structure Abbrev Name. Value must match in all cases.
    # It should all ready match the color table.
    # o_entry has Value Structure Abbrev Name and c_R c_G c_B c_A and Level 1 .. N.
    # c_entry has Value Structure Abbrev Name and c_R c_G c_B c_A.
    # 
    # We must trust value on n_a
    # We take for granted that n_a abbrev, name and structure could be different from either color table or ontology.
    # We should trust the data of o_entry the most. EXCEPT for value!
    $o_entry->{"Value"}    =$n_a{"Value"};
    
    $c_entry->{"Value"}    =$o_entry->{"Value"};
    $c_entry->{"Name"}     =$o_entry->{"Name"};
    $c_entry->{"Abbrev"}   =$o_entry->{"Abbrev"};
    $c_entry->{"Structure"}=$o_entry->{"Structure"};


    if ( 0
	 || $c_entry->{"Value"}==215
	 || $c_entry->{"Value"}==634
	 || $c_entry->{"Value"}==635
	 || $c_entry->{"Value"}==761
	 || $c_entry->{"Value"}==762
	 || $c_entry->{"Value"}==764
	 || $c_entry->{"Value"}==809
	 || $c_entry->{"Value"}==811
	){
	if ( defined($o_entry) ) {
	    dump($o_entry);}
	if ( defined($c_entry) ) {
	    dump($c_entry);}
    }
    #next;
    if ( not defined($o_entry) ) {
    	dump(%n_a);
	if ( defined ($c_entry) ) {
	    dump($c_entry ) ;}
	if ( 0
	     || $c_entry->{"Value"}==634
	     || $c_entry->{"Value"}==635
	     || $c_entry->{"Value"}==761
	     || $c_entry->{"Value"}==762
	     || $c_entry->{"Value"}==764
	     || $c_entry->{"Value"}==799
	     || $c_entry->{"Value"}==809
	    ){
	} else {
	    #exit;
	}
    }
    #next;
    
    
    #if (! defined ($alt_name) ) {
    #$alt_name=$Abbrev;
    #$n_a{"Name"}=$Abbrev;
    #}

    if ( 0) {#DISABLEDCURRENTLY
    my @c_vals=qw(c_R c_G c_B c_A Value);
    #my $o_entry=$o_table;
    #foreach (@c_vals){
	# set o_entry $_ to c_entry $_
	#$o_entry->{"$_"}=$c_entry->{"$_"};
    #}
    # set the o_entry color info to the c_table info.
    #$o_entry->{@c_vals}=$c_entry->{@c_vals};
    @{$o_entry}{@c_vals}=@{$c_entry}{@c_vals};
    } #DISABLEDCURRENTLY
       
    my $alt_name=$o_entry->{"Name"};
    #my $Abbrev=$n_a{"Abbrev"};
    my $Abbrev  =$o_entry->{"Abbrev"};
    my $value   =$o_entry->{"Value"};
    my $parent_hierarchy_node_id=$rootHierarchyNodeID;
    my $parent_ref=$rootHierarchyNode;
    my $model_display_template;
    my $hierarchy_template;
    if (! defined ($alt_name) ) { die("NAME FAILURE");}
    my @vtkMRMLModelDisplayNodes;
    #print("dumping right now just forstesting\n");dump ($parent_ref); exit;
    #mrml_attr_search($mrml_data,"id",$parent_ref->{"displayNodeID"}."\$","ModelDisplay");# this may not be what i'm looking to do.

    if ( exists ($mrml_model->{"displayNodeRef"} ) ) {
	@vtkMRMLModelDisplayNodes=mrml_attr_search( $mrml_data,"id",'^'.$mrml_model->{"displayNodeRef"}.'$',"ModelDisplay");# this may not be what i'm looking to do.`
    } elsif ( exists ($parent_ref->{"displayNodeID"} ) ) {
	@vtkMRMLModelDisplayNodes=mrml_attr_search( $mrml_data,"id",$parent_ref->{"displayNodeID"}.'$',"ModelDisplay");    # this gets the root hierarchy node's modeldisplaynode.
	warn("WARN: Using root display node for template.");
	
    } else {
	warn("WARN: Had to just grab the first ModelDisplay due to missing root");
	# if we dont have a parent node, then just get the first one, hope its the right thing.
	@vtkMRMLModelDisplayNodes=mrml_find_by_id($mrml_data,$mrml_nodes[0]->{"displayNodeRef"}."\$"); 
	if ( scalar(@vtkMRMLModelDisplayNodes) == 0 || ! keys %{$vtkMRMLModelDisplayNodes[0]} ){
	    dump($parent_ref);
	    die "Parent ref problem";
	}
    }
    $vtkMRMLModelDisplayNodes[0]->{"opacity"}=0.7;
    $vtkMRMLModelDisplayNodes[0]->{"visibility"}="false";
    my @model_color=split(" ",$vtkMRMLModelDisplayNodes[0]->{"color"});
    #$c_entry # could add this color to our color table in case its missing.
    $model_display_template = \%{clone $vtkMRMLModelDisplayNodes[0]};
    # could set any favored setting right here.
    # decided to set it before we grab the template.
    # $model_display_template->{"THINGY"}=VALUEDESIRED;
    #$model_display_template->{"opacity"}="0.7";
    #dump($model_display_template);
    $hierarchy_template = \%{clone $parent_ref};
    $hierarchy_template->{"expanded"}="false";
    #dump($hierarchy_template);
    my $sort_val=$#{$mrml_data->{"MRML"}->{"ModelHierarchy"}}; # current count of modelhierarchy nodes
    $hierarchy_template->{"sortingValue"}=$sort_val;
    #exit;
    #  while level_next exists, check for level, add it
    # grep {/Level_[0-9]+$/} keys %$o_entry;
    #dump($o_entry);
    print("Getting ready to processnode $alt_name\n") if $debug_val>=25;
    print("Fetching levels for $alt_name") if $debug_val>=45;
    my @parts=sort(keys %$o_entry); # get all the info types for this structure sorted.
    @parts=grep {/^Level_[0-9]+$/} @parts; # pair that down to only different ontology levels.
    if (scalar(@parts)>0 ) {
	print("\t got ".scalar(@parts)."\n") if $debug_val>=45;
	#dump(%$o_entry); # this works.
	#dump(%{$o_entry{@parts}}); # this doesnt.
	#dump(%{$o_entry}); this works
	#dump(@{$o_entry}{@parts});# THIS WORKS!!!!
	#dump($o_entry->{@parts});# this is undef
	#dump(@$o_entry->{@parts});# not an array reference
	#dump(@$o_entry{@parts});# THIS WORKS!
	@parts=@{$o_entry}{@parts}; # Now get the values at each present level. 
    } else {
	@parts=();
    }
    print("\t(\"".join("\", \"",@parts)."\")\n")  if $debug_val>=45;
    #next;
    my $ref;#=\%onto_hash;
    my @parent_hierarchy_names=($parts[$#parts]);# In simple mode, there is only one parent hierarchy name.
    if (keys %{ $ontology } ) {# if we're the new ontology in memory code.
	if (exists($o_entry->{"DirectAssignment"}) ) {
	    @parent_hierarchy_names=@{$o_entry->{"DirectAssignment"}};
	} else {
	    print("Bad structure,\t");
	    dump($o_entry);
    	    die("no entries in hierarchy. DirectAssignmentsNotSpecified");
	}
	if(scalar(@parent_hierarchy_names)<1 ) {
	    die("Bad structure, no entries in hierarchy.");
	} else {
	    printd(65,"\tparent hierarchy name: ".join(" ",@parent_hierarchy_names).".\n");
	}
	@parts=@parent_hierarchy_names;# for all direct assignments, get their parent.
	#print ("YES-keys\n");
	# commented out this hierarchy check... without it we dont build the rest of our tree.
	#if ( scalar(@parent_hierarchy_names)>1 ){ 
	    for my $assign (@parts) {
		my $test=$assign;
		while(exists( $ontology->{"Twigs"}->{$test} ) ){#while not a root node, add to list, and get ready to test next.
		    ($test)=keys(%{$ontology->{"Twigs"}->{$test}});
		    push(@parts,$test);
		}
	    }
	    @parts=uniq(@parts);
	    #dump(@parts);
	    @parts = sort { $ontology->{"SuperCount"}->{$b} <=> $ontology->{"SuperCount"}->{$a} } @parts;
	    print("\tMultiAssignment(".join(" ",@parts).")\n") if ($debug_val>=25);
	    
        #} else { print("\tSingleAssignment\n") if ($debug_val>=35);}
    }
    if (scalar(@parts)<1 ) {
	die("NO PARTS TO ASSIGN ontology line:".$o_entry->{"t_line"}."\n");
    }
    #dump(@parts);next;
    my $level_show_bool=0; # bool to show what levels we've got when this loop ends. This is used to show error messages.
    for(my $pn=0;$pn<=$#parts;$pn++){
	# proccess the different levels of ontology, get the different ontology names, create a path to save the structure into.
	#
	my $branch_name=$parts[$pn];#meta structure name
	trim($branch_name);		
	my $tnum="";
	($tnum,$branch_name)= $branch_name =~/^([0-9]*_)?(.*)$/;
	$tnum="" unless defined $tnum;
	#universally trash tnum.
	$tnum="";
	$branch_name=~ s/[,\/# ]/_and_/xg;#clean structure name of dirty elements replacing them with _and_.
	$branch_name=~ s/[-\/# ]/_to_/xg;#clean structure name of dirty elements replacing them with _to_.
	$branch_name=~ s/[,\/# ]/_/xg;#clean structure name of remaining dirty elements replacing them for underscores(commas forwardslashes poundsigns and spaces).
	$branch_name=~ s/__+/_/xg;  # Collapse any number of double underscore to single
	if ( ( 0 )
	     # THIS IS NOT DEACTIVATING THIS CODE, THIS IS FOR READABILITY LINEING THE CONDITIONS UP ON SUBSEQUENT LINES.
	     || ( not defined $branch_name ) 
	     || ( $branch_name eq '' ) 
	     || ( $branch_name =~ /^\s*$/ )
	     || ( $branch_name eq '0' ) 
	    ) {
	    warn("bad tree name($branch_name), skipping to additional levels");
	    $level_show_bool=1;
	    next; 
	}
	if (! keys %{ $ontology } ) {
	    if ( ( $branch_name =~ /_to_/x )
		 || ($branch_name =~/_and_/x) ){
		warn('DIRTY MULTI NAME, LAMELY TAKING JUST THE FIRST.');
		my @b_parts=split("_to_",$branch_name);
		my @b_parts2=split("_and_",$branch_name);
		if ($#b_parts<$#b_parts2) {
		    @b_parts=@b_parts2;
		}
		print("branch: $branch_name ");
		dump(@b_parts);
		$branch_name=$b_parts[0];
	    } 
	}
	if  ( ! keys %{ $ontology } 
	    && $branch_name =~ /^[rmp][0-9]{1,2}(?:[^\w]+[\w]*)?$/x) {
	    warn("\tAlex said to skip these structures($branch_name)");
	    next;
	}
	my $part_node_display_id=$tnum.$branch_name."Display";
	my $part_node_hierarchy_id=$tnum.$branch_name."Hierarchy";
	my $node_exists_bool=0;
	if (keys %{ $ontology } ) {# if we're the new ontology in memory code.
	    #if ( ! exists $ontology->{"Twigs"}->{$tnum.$branch_name} && exists $ontology->{"Hierarchy"}->{$tnum.$branch_name} ) {
	    #}
    	    #if ( ! exists $ontology->{"Twigs"}->{$tnum.$branch_name} ) {  # this code works, but its duplicataive.
	    # IF not exist, This node had no parents,and we're a direct root node.
	    #}
	    printd(65,"\tFinding parent $branch_name\n");
	    if ( exists $ontology->{"Hierarchy"}->{$tnum.$branch_name} ) {
		# IF exist, This node is a direct root node.
		printd(85,"\tRoot node\n");
		if ( exists $ontology->{"Twigs"}->{$tnum.$branch_name} ) {
		    die "PARENT DETECTION FAILURE";
		}
		#print("Parent check Hierarchy TRUE\n");
		$parent_hierarchy_node_id=$rootHierarchyNodeID;
		#$hierarchy_template = \%{clone $parent_ref};
		$ref=$ontology->{"Hierarchy"};
	    } elsif ( exists $ontology->{"Twigs"}->{$tnum.$branch_name} ) {
		my ($par_name) = keys(%{$ontology->{"Twigs"}->{$tnum.$branch_name}});
		my $grand_name="";
		if ( exists($ontology->{"Twigs"}->{$par_name}) ) {
		    #print("\tHasGrandparent\n");
		    #($grand_name) = keys(%{$ontology->{"Twigs"}->{$par_name}});
		}
		$ref=$ontology->{"Branches"}->{$par_name};
		#OH BOLLOCKS I NEED THE PARENTS PARENT FOR THIS TO BE RIGHTEOUS, wait, no i dont.... that only happens for leaves.
		$parent_hierarchy_node_id=$grand_name.$par_name."Hierarchy";# COULD BE PROBLEMS WITH tnum HERE> We're effictively ommiting it right now.
		#$hierarchy_template = \%{clone $parent_ref};
		#dump(%$ref);
	    } else {
		#dump($ontology->{"Twigs"});
		dump(keys(%{$ontology->{"Branches"}}));
		dump($ontology->{"Branches"}->{$tnum.$branch_name});
		dump($ontology->{"Hierarchy"});
		die ("DEADEND with $branch_name, orphaned branch?") unless $debug_val>70;
	    }
	    if ( ! exists ($ref->{$tnum.$branch_name}) ) {
		print("ERRROR: Branch not available\n");
		dump (%$ref);
	    }
	    # Check if this node has been defined already.
	    #OH Ho, needed exact find!
	    printd(65,"\tSearching for ModelHierarchy $part_node_hierarchy_id\n");
	    my $l_debug=$debug_val;
	    $debug_val=49;
	    my @existing_nodes=mrml_find_by_id($mrml_data,'^'.$part_node_hierarchy_id.'$',"ModelHierarchy");
	    $debug_val=$l_debug;
	    if (scalar(@existing_nodes)>0 ){
		$node_exists_bool=1;
	    }
	}
	#print($tnum.$branch_name." HRD EXIT\n"); exit;
	#print($tnum.$branch_name." SKIPPER\n"); next;
	if ( ! exists($ref->{$tnum.$branch_name}) || ! $node_exists_bool ) {
	    # clever way to build hierarchy hash on fly. The hierarchy hash is just a holder for the structure.
	    # It was only used here to keep track of whether we've sceen this node before or not.
	    my $spc=sprintf("  "x$pn);#indent nspaces times...
	    print("$spc$branch_name($part_node_display_id,$part_node_hierarchy_id) not there, adding ... \n") if ($debug_val>=25);
	    if (! keys %{ $ontology } ) {# not the new ontology in memory code.
		warn("OlderBadderCode\n");
		$ref->{$tnum.$branch_name}={};} # declare our empty ref so we can continue filling it in
	    # update template with values for this structure.
	    $model_display_template->{"name"}=$branch_name."_";
	    $model_display_template->{"id"}=$part_node_display_id;
	    if ( 1 ) { #WHEN WE'RE TESTING WE WANT CONSTANT COLOR FOR INVENTED STRUCTURES SO I CAN DO A DIFF.
		# This grabs the first three letters of the branch name, so that its predictable, constant, and colored
		# This is a rather goofy way to handle the constant color issue, slicer color is 0-1 so we divide by 255 since thats normal char range.
		my @nums=unpack("W*",$branch_name);
		push @nums, 128 x ( 3 - @nums ) ;# ensure nums is at least 3 big.
		#@nums=@nums[0..2]; $_ /= 255 for @nums;# works with unin int warning THE WARNING WAS FOR SHORT STRUCTURES
		my @tmp=@nums;
		#@nums=@nums[0..2]; $_ = int($_)/255 foreach @nums; # if would be good to get this to a min of 0.5 
		@nums=@nums[0..2]; $_ = int($_)/127 foreach @nums;

		# first element only...
		#$model_display_template->{"color"}=sprintf("%0.0f ",@nums);
		#$model_display_template->{"color"}=sprintf("%0.0f %0.0f %0.0f",
		$model_display_template->{"color"}=sprintf("%f %f %f",
							   #,rand(1),rand(1),rand(1));
							   $nums[0],$nums[1],$nums[2]);
		#,$nums[0]/255,$nums[1]/255,$nums[2]/255);
	    } elsif( 0 ) { #WHEN WE'RE TESTING WE WANT CONSTANT COLOR FOR INVENTED STRUCTURES SO I CAN DO A DIFF.
		$model_display_template->{"color"}=sprintf("%0.0f %0.0f %0.0f"
							   ,0.25,0.25,0,25);
	    } else {
		$model_display_template->{"color"}=sprintf("%0.0f %0.0f %0.0f"
							   ,rand(1),rand(1),rand(1));
	    }
	    $model_display_template->{"visibility"}="false";
	    $hierarchy_template->{"name"}=$branch_name;
	    $hierarchy_template->{"id"}=$part_node_hierarchy_id;
	    $hierarchy_template->{"parentNodeRef"}=$parent_hierarchy_node_id;
	    $hierarchy_template->{"displayNodeID"}=$model_display_template->{"id"};
	    if ( ! exists( $hierarchy_template->{"sortingValue"} ) ) {
		$hierarchy_template->{"sortingValue"}=1;}
	    $hierarchy_template->{"sortingValue"}=$hierarchy_template->{"sortingValue"}+1;
	    $hierarchy_template->{"expanded"}="true";
	    # now add the template to MRML->ModelHierarchy and MRML->SceneView->ModelHierarchy
	    #push(@{$mrml_data->{"MRML"}->{"ModelHierarchy"}},%{clone $hierarchy_template});
	    push(@{$mrml_data->{"MRML"}->{"ModelHierarchy"}},\%{clone $hierarchy_template});
	    push(@{$mrml_data->{"MRML"}->{"ModelDisplay"}},\%{clone $model_display_template}); 
	    push(@{$mrml_data->{"MRML"}->{"SceneView"}->{"ModelHierarchy"}},\%{clone $hierarchy_template});
	    push(@{$mrml_data->{"MRML"}->{"SceneView"}->{"ModelDisplay"}},\%{clone $model_display_template});
	}
	if (! keys %{ $ontology } ) {# not the new ontology in memory code.
	    $ref=$ref->{$tnum.$branch_name}; # this is our destination point for our structure once we've ensured the whole hierarchy before it is built.
	    $parent_hierarchy_node_id=$tnum.$branch_name."Hierarchy";
	}
	#print("."x$pn);
	#print("\n");
    } 
    if ( $level_show_bool ) {
	# Some levels haed issues here they all are.
	warn("bad tree name in group ( ".join(@parts," ")." ), skipping to additional levels");
    }
    #@vtkMRMLHieraryNodes=mrml_attr_search($mrml_data,"associatedNodeRef",$rootHierarchyNodeID."\$","ModelHierarchy");
    # if the ref dont exist, we add it... hmm how/when do we set the type to vtkMRMLModelHierarchyNode?
    #printf("--template_val--");
    #dump($hierarchy_template);
    #dump($mrml_data->{"MRML"}->{"ModelHierarchy"});
    #dump($mrml_data->{"MRML"}->{"SceneView"}->{"ModelHierarchy"});
    #dump($mrml_data->{"MRML"}->{"ModelDisplay"});
    #dump($mrml_data->{"MRML"}->{"SceneView"}->{"ModelDisplay"});
    #### END OLD MULTI_LEVEL PARTS CODE
    #dump(%onto_hash);
    #dump(%{$ref});
    #dump(%l_1);
    #exit;
    # next;
    my $node=$mrml_model;
    #display_complex_data_structure($node);

    my $storage_node_id;
    my $storage_node;
    #
    # Assign Structure to its parent node(s)
    #
    #    my $parent_hierarchy_node_id="BOGUS";
    # this is currently the singular parent code. For multi-parentage, we'll have to duplicate the modelhierarchy entry for each alternate parent.
    my $mrml_node_id=$mrml_model->{"id"};    
    if ( defined $mrml_node_id  ) {
	my @model_hierarchy_nodes=mrml_attr_search($mrml_data,"associatedNodeRef",'^'.$mrml_node_id.'$',"ModelHierarchy");
	if(scalar(@model_hierarchy_nodes)>1){
	    warn("Multiple Hierarchy Input Nodes");
	}
	$storage_node_id=$mrml_model->{"storageNodeRef"};
	
	#print("found ".($#model_hierarchy_nodes+1)." references to this node\n");
	my $m_h_node={};
	for(my $n_n=0;$n_n<scalar(@model_hierarchy_nodes);$n_n++){
	    $m_h_node= $model_hierarchy_nodes[$n_n];
	    #print("change node $m_h_node->{id} $m_h_node->{name} to $alt_name\n");
	    if (! exists($m_h_node->{"id"} ) ) {
		warn("Bad node ");
		dump($m_h_node);
	    }
	    if($rename_type eq 'Clean' ){
		$m_h_node->{"name"}="$alt_name";
	    } elsif($rename_type eq 'Structure' ){ #was modelfile
		$m_h_node->{"name"}="$model_prefix${value}_$alt_name";
		$mrml_model->{"name"}="$model_prefix${value}_$alt_name";
	    } elsif( $rename_type eq 'Name')  { #name?
		$m_h_node->{"name"}="$alt_name";
		$mrml_model->{"name"}="$alt_name";
	    } elsif( $rename_type eq 'Abbrev')  { 
		$m_h_node->{"name"}="$Abbrev";
		$mrml_model->{"name"}="$Abbrev";
	    } else { 
		$m_h_node->{"name"}="$model_prefix${value}_$alt_name";
		$mrml_model->{"name"}="$model_prefix${value}_$alt_name";
	    }
	}
	#	dump(@parent_hierarchy_names);exit;
	if ( exists($m_h_node->{"id"} ) ) {
	    my $m_h_base_id=$m_h_node->{"id"};
	    my $m_m_base_id=$mrml_model->{"id"};
	    #push(@{$mrml_data->{"MRML"}->{"Model"}},\%{clone $mrml_model});
	    #push(@{$mrml_data->{"MRML"}->{"SceneView"}->{"Model"}},\%{clone $mrml_model});
	    my $p_c=0;
	    if ( ! scalar(@parent_hierarchy_names)>=1 ) {
		die ("NO PARENTS");
	    }
	    for my $parent_name ( @parent_hierarchy_names) {
	    #if ( 1 ) {
		#my $parent_name="";
		my $grand_name="";
		#if ( exists($ontology->{"Twigs"}->{$parent_name}) ) {
		    #print("Has grand parent ".join('',keys(%{$ontology->{"Twigs"}->{$parent_name}}))."\n");
		    #($grand_name) = keys(%{$ontology->{"Twigs"}->{$parent_name}});
		#}
		my $cur_node=$mrml_model;
		$m_h_node->{"sortingValue"}=$processed_nodes;
		if ($p_c>0) {
		    $cur_node=\%{clone($mrml_model)};
		    #$m_h_node->{"sortingValue"}=$m_h_node->{"sortingValue"}+1;
		}
		$cur_node->{"id"}=$parent_name.$m_m_base_id;
		$m_h_node->{"parentNodeRef"}=$parent_name."Hierarchy";
		$m_h_node->{"associatedNodeRef"}=$cur_node->{"id"};
		$m_h_node->{"id"}=$parent_name.$m_h_base_id;
		if ($p_c>0) {
		    push(@{$mrml_data->{"MRML"}->{"Model"}},\%{clone $cur_node});
		    push(@{$mrml_data->{"MRML"}->{"SceneView"}->{"Model"}},\%{clone $cur_node});
		}
		push(@{$mrml_data->{"MRML"}->{"ModelHierarchy"}},\%{clone $m_h_node});
		push(@{$mrml_data->{"MRML"}->{"SceneView"}->{"ModelHierarchy"}},\%{clone $m_h_node});
		$p_c++;
	    }
	} else {
	    warn("NO ID FOR NODE!");
	    dump($m_h_node);
	}

    } else {
	if (!scalar $mrml_model ){
	    warn("OHh NOOOO node id not set ! Sleeping a bit while you look at this!");
	    dump($mrml_model);
	    sleep_with_countdown(15);
	} else {
	    warn("$alt_name not found!");
	}
	next;
    }

    
    my @s_nodes=mrml_attr_search($mrml_data,"id",$storage_node_id."\$","ModelStorage");
    $storage_node=$s_nodes[0];
    my $file_src;#="Static_Render/ModelTree/$file_name.vtk";
    if ( scalar %{$storage_node} ) {
	$file_src=$storage_node->{"fileName"};
	#my ($Tn,$Tp,$Te)=fileparse($p_color_table_in);
	($Tn,$Tp,$Te)=fileparts($file_src,2);
    } else {
	#warn("Using assumed source filename");
	warn("No source filename!!!!");
	next;
    }
    my $file_name=$Tn;
    my $file_dest='Static_Render/ModelTree/'.join('/',@parts)."/$file_name.vtk";
    #$file_dest="$s_path/$file_name.vtk";
    $file_dest=~ s/[ ]/_/gx;
    my @c_path=($file_src,$file_dest);
    if ( ! -f $file_dest) { 
	if ( -e $file_src ) { 
	    #push(@c_name,$file_name.".vtk");
	    print("mv $file_src $file_dest\n") if ($debug_val>=45);
	    if ( $do_unsafe ) {
		rename($file_src, $file_dest);
	    }
	} else {
	    print ("\t #missing $file_src\n") if ($debug_val>=30);
	}
    } else {
	#rename($file_dest,$file_src);
	push(@missing_model_messages,"File already in place: $file_dest");
    }
    if ( scalar %{$storage_node} && $do_unsafe) {
	print("setting new file path in mrml\n");
	$storage_node->{"fileName"}=$file_dest;
    }
    #$ref->{$alt_name}=$value;
    if( 0 ) 
    {# safe but ugly name_handle
	my( $alt_name,$c_fn);
	my $file_name="$model_prefix\[0-9]+_${alt_name}";
	$alt_name=~ s/,[ ]/CMA/gx;
	$alt_name=~ s/[ ]/SPC/gx;
	$alt_name=~ s/,/CMA/gx;
	$alt_name=~ s/\//FSLASH/gx;
	$alt_name=~ s/\+/PLS/gx;
	#$alt_name=~ s/\(/\\(/gx;
	#$alt_name=~ s/\)/\\)/gx;
	$c_fn=$alt_name;
    }
    $processed_nodes++;
}
print("processed $processed_nodes/".scalar(@mrml_nodes)." nodes\n");
dump(sort(@missing_model_messages));

printf("ontology built\n");
mrml_to_file($mrml_data,'  ',0,'pretty','',$p_mrml_out);
# for each line of color table?
# get value, name|abbrev|structure(whichever we've requeseted) c_r, c_g, c_b, c_a
printf("Dumping new color_table to $p_color_table_out\n");
my @color_table_out=();
my @fields=("Value", $rename_type,qw( c_R c_G c_B c_A));# this is a constant orde,r so this is ok, our ontology is not.
my $test_line=0; # counter to help put lines back out in order.
my $max_failures=200;
while( (scalar(@color_table_out) <= scalar(keys %{$c_table->{"t_line"}}) ) 
       && ( $test_line < ( scalar(keys %{$c_table->{"t_line"}})+$max_failures ) ) ) {
    #printf("%i < %i\n ",$test_line, (scalar(keys  %{$c_table->{"t_line"}})+$max_failures) );
    # we're trying to traverse the color table lines,
    # so while we have less outputs than inputs, AND we havent tried 200 more times 
    if ( exists($c_table->{"t_line"}->{$test_line}) ){
	my $c_entry=$c_table->{"t_line"}->{$test_line};
	my $line;
	foreach (@fields) {
	    if (! exists $c_entry->{$_} ){
		printf($c_entry->{"Name"}." missing $_\n");
		$c_entry->{$_}=0;
		}
	}
	$line=join(" ",@{$c_entry}{@fields})."\n";
	push(@color_table_out,$line);
    }
    $test_line++;
}
write_array_to_file($p_color_table_out,\@color_table_out);
#
# Save ontology, and derrived listings
#
my @ontology_out=();
#my @o_columns=keys %{$o_table->{'Header'}};#keys %$o_table;
#@fields=qw(Structure Abbrev Level_1 Level_2 Level_3 Level_4 Value c_R c_G c_B c_A);# this was fine for the colortable as it had no header, but we can do better here.
@fields=();
#dump(%{$o_table->{"Header"}});#exit;
# this is the hash converstion code lets use it to build an inverse hash.. 
my %h_o_hash;@h_o_hash{values(%{$o_table->{"Header"}})}=keys(%{$o_table->{"Header"}});#dump(%h_o_hash);#exit;
foreach my $idx (sort {$a<=>$b} (keys(%h_o_hash)) ) {# HAD TO FORCE NUMERICAL OR THIS WOULDNT WORK AS EXPECTED.
    push(@fields,$h_o_hash{$idx});
}
#dump(@fields);exit;
push(@ontology_out,join("\t",@fields)."\n");
$test_line=0;
printf("Dumping new ontology to $p_ontology_out\n");
while( (scalar(@ontology_out) <= scalar(keys %{$o_table->{"t_line"}}) ) 
       && ( $test_line < ( scalar(keys %{$o_table->{"t_line"}})+$max_failures ) ) ) {
    #printf("%i < %i\n ",$test_line, (scalar(keys  %{$o_table->{"t_line"}})+$max_failures) );
    # we're trying to traverse the color table lines,
    # so while we have less outputs than inputs, AND we havent tried 200 more times 
    if ( exists($o_table->{"t_line"}->{$test_line}) ){
	my $o_entry=$o_table->{"t_line"}->{$test_line};
	if ( 1 ) {
	} else {
	    # my $c_entry;
	    # if ( ! defined $c_entry ){
	    # 	$c_entry=$c_table->{"Value"}->{$o_entry->{"Value"}};
	    # 	if ( defined($c_entry) && $debug_val>=45) {
	    # 	    print("\tcolor by Value\n");
	    # 	}#dump($c_entry);}
	    # }
	    # if ( ! defined $c_entry ){
	    # 	$c_entry=$c_table->{"Structure"}->{$o_entry->{"Structure"}};
	    # 	if ( defined($c_entry) && $debug_val>=45) {
	    # 	    print("\tcolor by Structure\n");
	    # 	    dump($o_entry);dump($c_entry);}
	    # }
	    # if ( ! defined $c_entry ){
	    # 	$c_entry=$c_table->{"Name"}->{$o_entry->{"Name"}};
	    # 	if ( defined($c_entry) && $debug_val>=45) {
	    # 	    print("\tcolor by Name\n");
	    # 	    dump($o_entry);dump($c_entry);}
	    # }
	    # if ( ! defined $c_entry ){
	    # 	$c_entry=$c_table->{"Abbrev"}->{$o_entry->{"Abbrev"}};
	    # 	if ( defined($c_entry) && $debug_val>=45) {
	    # 	    print("\tcolor by Abbrev\n");
	    # 	    dump($o_entry);dump($c_entry);}
	    # }
	    
	    # if ( 0
	    # 	 || $o_entry->{"Value"}==215
	    # 	 || $o_entry->{"Value"}==634
	    # 	 || $o_entry->{"Value"}==635
	    # 	 || $o_entry->{"Value"}==761
	    # 	 || $o_entry->{"Value"}==762
	    # 	 || $o_entry->{"Value"}==764
	    # 	 || $o_entry->{"Value"}==809
	    # 	 || $o_entry->{"Value"}==811
	    # 	 || $o_entry->{"t_line"}>=818
	    # 	){
	    # 	if ( defined($o_entry) ) {
	    # 	}#dump($o_entry);}
	    # 	if ( defined($c_entry) ) {
	    # 	}#dump($c_entry);}
	    # }
	    # #$test_line++;
	    # #next;
	    # if (0 && ! defined $c_entry ){
	    # 	my @c_vals=qw(c_R c_G c_B c_A);
	    # 	#my @c_vals=qw(c_R c_G c_B);
	    # 	@{$o_entry}{@c_vals}=(255) x scalar(@c_vals);
	    # 	$o_entry->{"c_A"}=0;
	    # 	$o_entry->{"Value"}=0;
	    # 	print("Extranous ontology entry($o_entry->{Structure}:$o_entry->{t_line})!\n");
	    # 	#sleep_with_countdown(2);
	    # } else {
	    # 	my @c_vals=qw(c_R c_G c_B c_A Value);
	    # 	# set the o_entry color info to the c_table info.
	    # 	#dump(@{$c_entry}{@c_vals});
	    # 	@{$o_entry}{@c_vals}=@{$c_entry}{@c_vals};
	    # }
	}
	my $line;
	my @values;
	my @bv_msg;
	for (my $vn=0;$vn<=$#fields;$vn++){
	    my $val=$o_entry->{$fields[$vn]};
	    if (! defined($val) ) {
		$val="";
	    } elsif( $fields[$vn] =~/^Level_[0-9]+$/x ) {
		my ($onum,$name)=$val=~/^([0-9]+_)?(.*)$/x ;
		# If our value starts with number_
		if ( (  defined($onum ) && defined($name)) 
		     &&(length($onum)>0 && length($name)>0) ) {
		    push(@bv_msg,"$fields[$vn]:$val ->$name");
		    $val=$name;
		}
	    }
	    push(@values,$val);
	}
	if (scalar($#bv_msg)>0 ){
	    print("DIRTY VALUE DETECTED... $o_entry->{t_line} ".join(", ",@bv_msg)."\n");
	    #sleep_with_countdown(3);
	}
	$line=join("\t",@values)."\n";
    	push(@ontology_out,$line);
    }
    $test_line++;
}
write_array_to_file($p_ontology_out,\@ontology_out);

my @super_structures_out=();
my @super_structures_hf=();
my @su_header=qw(Name Values);
push(@super_structures_out,join("\t",@su_header)."\n");
push(@super_structures_hf,"#".join("\t",@su_header)."\n");
my @super_structs=keys(%{$ontology->{"SuperStructures"}});
@super_structs = sort { $ontology->{"SuperCount"}->{$b} <=> 
			    $ontology->{"SuperCount"}->{$a} } keys(%{$ontology->{"SuperCount"}});
for my $super(@super_structs) {
    my @val_input=@{$ontology->{"SuperStructures"}->{$super}};
    my @val_output;
    if ( $super eq "r3"
	 || $super eq "r4"
	){
	#dump(@val_input);#next;
    }
    while (my $line_num=shift(@val_input)) {
	if ( exists($o_table->{"t_line"}->{$line_num})
	     &&  exists($o_table->{"t_line"}->{$line_num}->{"Value"})
	     &&  $o_table->{"t_line"}->{$line_num}->{"Value"} !=0 ) {
	    push(@val_output,$o_table->{"t_line"}->{$line_num}->{"Value"});
	} elsif ( exists($o_table->{"t_line"}->{$line_num}->{"Value"}) ) {
		print("$super line $line_num broken_value.\n");
		##dump($o_table->{"t_line"}->{$line_num});
	} else {
	    print("$super line $line_num removed\n");
	}
    }
    #sort {$a<=>$b}
    @val_output=sort {$a<=>$b} (@val_output);# force numerical sort using the curly brace stuff
    #my $line=join("\t",$super,join(",",@val_output)."\n"); 
    my $line=sprintf("%s\t%s\n",$super,join("\t",@val_output)); 
    push(@super_structures_out,$line);
    $line=sprintf("%s=%i:1,%s\n",$super,scalar(@val_output),join(" ",@val_output)); 
    push(@super_structures_hf,$line);
}
print("Writing meta structure componenets sheet $p_ontology_structures_out\n");
write_array_to_file($p_ontology_structures_out,\@super_structures_out);
print("Writing meta structure componenets headfile $p_ontology_structures_out_hf\n");
write_array_to_file($p_ontology_structures_out_hf,\@super_structures_hf);

#sub lptr {
#{
#    my ($big_onto,$tree)=@_;
my @level_election=();
@fields=();
%h_o_hash=();
@h_o_hash{values(%{$ontology->{"SuperLevel"}->{"Header"}})}=keys(%{$ontology->{"SuperLevel"}->{"Header"}});
dump(%h_o_hash);#exit;
foreach my $idx (sort {$a<=>$b} (keys(%h_o_hash)) ) {# HAD TO FORCE NUMERICAL OR THIS WOULDNT WORK AS EXPECTED.
    push(@fields,$h_o_hash{$idx});
}
#dump(@fields);exit;
push(@level_election,join("\t",@fields)."\tBestLevel\n");
printf("Dumping new ontology levels to \n");
for my $super(@super_structs) {
    # for all stuper structures, get their level votes, add the "BEST guess" column which is level of their highest count.

    my $l_entry=$ontology->{"SuperLevel"}->{$super};
    
    #if ( exists($o_table->{"t_line"}->{$test_line}) ){
    #my $o_entry=$o_table->{"t_line"}->{$test_line};
    my $line;
    my @values;
    #my @bv_msg;
    my $max_found=0;
    my $best_level=0;
    for (my $vn=0;$vn<=$#fields;$vn++){
	my $val=$l_entry->{$fields[$vn]};
	if (! defined($val) ) {
	    $val=0;
	} 
	if( $fields[$vn] =~/^Level_[0-9]+$/x ) {
	    if ($val>$max_found) {
		$max_found=$val;
		$best_level=$fields[$vn];
	    }
	    #my ($onum,$name)=$val=~/^([0-9]+_)?(.*)$/x ;
	    # If our value starts with number_
	    #if ( (  defined($onum ) && defined($name)) 
	    #&&(length($onum)>0 && length($name)>0) ) {
	    #push(@bv_msg,"$fields[$vn]:$val ->$name");
	    #$val=$name;
	    #}
	}
	push(@values,$val);
    }
    push(@values,$best_level);
    $line=join("\t",@values)."\n";
    push(@level_election,$line);
    #}
}
write_array_to_file($p_ontology_levels_out,\@level_election);
#}

#
# dump the lines_to_struct info for debugging.
#
my @assignment_list=();
my @lines=sort {$a<=>$b} (keys(%{$ontology->{"line_to_struct"}}));
for my $line_num(@lines){
    if (exists($o_table->{"t_line"}->{$line_num}) ) {
	my $o_entry=$o_table->{"t_line"}->{$line_num};
	my @super_out;
	if (   exists($o_entry->{"Value"})
	       &&  $o_entry->{"Value"} !=0 ) {
	    #@super_out=@{$ontology->{"line_to_struct"}->{"$line_num"}};
	    if ( exists($ontology->{"line_to_struct"}->{"$line_num"}) ) {
		@super_out=@{$ontology->{"line_to_struct"}->{"$line_num"}};
	    } else {
		warn("Odd, no direct assignments for $o_entry->{t_line}");
		dump($o_entry);
	    }
	    unshift(@super_out,scalar(@super_out));
	    my $line=sprintf("%s\t%s\n",$o_entry->{"Value"},join("\t",@super_out)); 
	    push(@assignment_list,$line);#print($line);
	} elsif ( exists($o_entry->{"Value"}) ) {
	    print("line $line_num broken_value.\n");
	} else {
	    warn("line $line_num invalid.");
	}
    } else {
	print("line $line_num removed\n");
    }
}

print("Writing structure assignments debug info $p_ontology_assignment_out\n");
write_array_to_file($p_ontology_assignment_out,\@assignment_list);


exit;exit;exit;
exit;exit;exit;
exit;exit;exit;



sub cleanup_ontology_levels {
    # This is a cleanup function, to make sure bad ontology data doesnt pollute what we're doing later on.
    # it needs to take the onotology hash table, and turn it into a hierarchical structure.
    #
    # Plan is to do this in two passes. First pass operates on each line of ontology; 
    # it ensures unique structure names/abbreviations/value, and adds levels to a listing of seen super structures.
    # The second pass goes through the seen super structures and tries to find their parent structure.
    #
    # Actual end point has us do several different passes over first the lines of the ontologly, then over the discovered structures. 
    my ($o_table,$c_table)=@_;
    my $onto_hash={}; #$onto_hash->{"test"}="foo";
    # onto_hash will have several parts.
    # onto SuperStructures, this is each discovered meta structure with any 
    #                       assigned leaves by the leaf line number.
    # onto order_lookup, the discovered meta structures with their ordering 
    #                    number if they've got one. Only the first number 
    #                    found will be used for any group.
    #                    this is prepended onto the name of the meta-structure
    #                    on the table to facilitate sorting.
    # onto SuperCount, the discovered meta structures with their leaf count.
    # onto SuperLevel, the discovered meta struccutres, and a vote count to 
    #                   set which level a particular structure should be on 
    #                   from the leaves result.
    # onto line_to_struct, lookup of linenumber to assigned SuperStructure, 
    #                    the inverse of SuperStructures.
    # onto Branches, once we have the SuperStructures and the SuperCount we 
    #                create the branches, this is the tree, without the leaves.
    # onto Twigs, as we generate the branches, whenever we discover a  
    #             particular structure has a parent its added to the twig  
    #             listing, this is a lookup of twigname -> parent name=parent name.
    # onto Hierarchy, any branch without a parent is a root hierarchy node, 
    #                 these are added here so that we can dump the hierarchy 
    #                 and see the full tree we've built.
    # onto LevelAssignments, As the levels of the hierarchy are discoverd 
    #                        we're going to write in their preference. We have
    #                        reason for several meta-structures to have 
    #                        the same contents. To handle that well, they need 
    #                        to be in the correct order in the input ontology.
    #                        This will serve as a way to maintain that,
    #                        preventing over assignment and pileup.

    
    my @o_columns=keys %{$o_table->{'Header'}};#keys %$o_table;
    #dump(@o_columns); #dump($o_table->{$o_columns[0]}); # a worse version of the commented test.
    #dump($o_table->{"t_line"}); # test that we have contents by line in our table.
    my $seen={}; # a hash of the expectedly unique keys of the hash.
    # our brainstem hierarchy broke the abbrevaiaiton uniqueness.
    # goint to try commenting this out just to see if that lets it process sucessfully.
    $seen->{"Value"}={};     # 
    $seen->{"Structure"}={}; #
    #$seen->{"Abbrev"}={};    #
    $seen->{"Name"}={};      #
    $seen->{"t_line"}={};    # by definition this should be unique, but we'll check anyway.
    my @onto_errors=();      # linenumbers of error.
    my @onto_error_msgs=();  # error messages generated as we process. To be displayed once we've looked at all lines.
    my $blank_entry; # blank entry.
    @{$blank_entry}{keys(%{$o_table->{"Header"}})}=(0) x scalar(keys(%{$o_table->{"Header"}}));#dump($blank_entry);exit;
    $blank_entry->{"Name"}=0;
    
    for my $onto_line (keys( %{$o_table->{"t_line"}}) ) {
	#$onto_line=817;
	my $o_entry=$o_table->{"t_line"}->{$onto_line};
	
	#
	# error check for blank entry.
	#
	# b_ignore puts any column which is only present in the ontology (and not in the blank) in ignore list
	my @b_ignore=grep(/join(|,keys(%$o_entry))/,keys(%$blank_entry));
	push(@b_ignore,"t_line");
	my $b_test=compare_onto_lines($blank_entry,$o_entry,@b_ignore);
	if(@b_ignore>1 ){
	    dump(@b_ignore);
	    sleep_with_countdown(3);
	}
	if ( ! keys %{ $b_test} ) {
	    print("BOGUS LINE $onto_line\n");dump($o_entry);remove_onto_line($o_table,$onto_line); next;
	    exit;
	} else {
	    #print("Not blank $onto_line\n");
	    #dump($b_test);#exit;
	}
	
	#
	# error check our o_entry for duplication.
	#
	my @error_fields=();
	my @conflicts;
	for my $check_field (keys(%$seen)) {
	    if ( ! exists($seen->{$check_field}->{$o_entry->{$check_field}})){ 
		# not seen, no prob.
		# $seen->{$check_field}->{$o_entry->{$check_field}} = ($o_entry->{$check_field});
	    } else {
		# Seen before, add conflicting line_numbers to the conflict list
		push(@conflicts,@{$seen->{$check_field}->{$o_entry->{$check_field}}}); 
		if ($check_field ne "Value" || $o_entry->{"Value"} != 0 ) {
		    # add to error listing ONLY when its not value==0.
		    push(@onto_errors,$seen->{$check_field}->{$o_entry->{$check_field}});
		    push(@onto_error_msgs,"ERROR duplicate ontology $check_field. Line ".
			 $o_entry->{"t_line"}." prev_count:".scalar(@{$seen->{$check_field}->{$o_entry->{$check_field}}}).".");
		    push(@error_fields,$check_field);
		}
	    }
	    push(@{$seen->{$check_field}->{$o_entry->{$check_field}}},$o_entry->{"t_line"}); # add to seen arrays.
	}
	@conflicts=uniq(@conflicts); # for many dupe fields the same line could be reported again
	my $auto_res=0;
	my $check_count=scalar(@conflicts);
	my $c_num=0;
	print("testing $o_entry->{t_line} ... ".join(" ",@conflicts)."\n") if ($check_count>0);
	while ($c_num<$check_count) {
	    my $conflict=shift(@conflicts);$c_num++;
	    if ( ! exists($o_table->{"t_line"}->{$o_entry->{"t_line"}}) ) {
		#print("AUTO_RES: Cur bogus\n");# we were removed
		print("$o_entry->{t_line} removed");
		$auto_res++;
		last;
	    }
	    my $alt_entry=$o_table->{"t_line"}->{$conflict};
	    my $test_status={};# a hasn to store which value is more likely correct.
	    #                    will add 1 to values for alt, and subtract one for current.
	    my $diff_=compare_onto_lines($o_entry,$alt_entry,qw(t_line));#,qw(c_R c_G c_B c_A t_line));
	    # value handling....
	    #if ( $
	    # @ignoreH{@ignore} = ();
	    # if ( scalar(@{$diff_})>0 ){
	    if (keys %{ $diff_} ) {
		# There were differences.
		# Is the color bogus(for either).
		my $c_test;
		#$c_test->{"Value"}=0;
		$c_test->{"c_R"}=255;
		$c_test->{"c_G"}=255;
		$c_test->{"c_B"}=255;
		# test o_entry color
		my @ignore=grep(!/join(|,keys(%$c_test))/,keys(%$o_entry));
		my $cur_d=compare_onto_lines($c_test,$o_entry,@ignore);
		my @bogus_color=(0,0);
		if ( ! keys %{ $cur_d} ) {
		    $bogus_color[0]=1;}
		# test alt_entry color
		@ignore=grep(!/join(|,keys($c_test))/,keys(%$alt_entry));
		$cur_d=compare_onto_lines($c_test,$alt_entry,@ignore);
		if ( ! keys %{ $cur_d} ) {
		    $bogus_color[1]=1;}
		my $v_err=0; # how many 0 values do we have.
		if ( $o_entry->{"Value"}==0 ) {
		    $v_err++;}
		if ( $alt_entry->{"Value"}==0 ){
		    $v_err++;}
		if ( $v_err!=2 ) { # One value is good.
		    if (! exists($diff_->{"Abbrev"})
			&& ! exists($diff_->{"Name"}) ) {
			# name and abbrev are the same, so we have some kinda clear winner.
			if ( $o_entry->{"Value"}!=0 && ! $bogus_color[0] && $bogus_color[1]) {
			    print("AUTO_RES: Alt bogus\n");
			    remove_onto_line($o_table,$alt_entry->{"t_line"});
			    $auto_res++;
			} elsif ( $o_entry->{"Value"}==0 && $bogus_color[0] && ! $bogus_color[1]) {
			    print("AUTO_RES: Cur bogus\n");
			    remove_onto_line($o_table,$o_entry->{"t_line"});
			    $auto_res++;
			    last;
			} else {
			    #no clear winnner
			}
			
		    }
		}  else {# both values are bogus,
		    if( exists($diff_->{"Abbrev"})      # and so is abbrev
			&& exists($diff_->{"Name"}) ) { # and name
			next;
		    }
		}
		# and name or abbrev are bougs.
		# Check if its our lovely value difference.
		if (exists($diff_->{"Value"})      # value is diff
		    && ! exists($diff_->{"Abbrev"})# but abbrev
		    && ! exists($diff_->{"Name"})  # and name are not
		    #&& ! exists($diff_->{"Structure"})
		    ) {
		    # If The value is different but name/abbrev/structure are the same
   		    if ($bogus_color[0] ){
			# DELETE CURRENT
			print("AUTO_RES: Current bogus\n");
			remove_onto_line($o_table,$o_entry->{"t_line"});
			next; # and skip to next line
		    } elsif($bogus_color[1] ){
			# DLETE ALT
			print("AUTO_RES: Alt bogus\n");
			remove_onto_line($o_table,$alt_entry->{"t_line"});
			$auto_res++;
		    } else {
			# COLOR NOT BOGUS, VALUE DIFFERENT ABBREV/NAME/STRUCTURE SAME
			# i dont think we have this caes, but just in case we do
			#push(@conflicts,$alt_entry->{"t_line"});
		    }
		    if ( exists($diff_->{"Abbrev"}) 
			 && exists($diff_->{"Name"})
			 && exists($diff_->{"Structure"})
			) {
			# if Value/name/abbrev/structure are diff... do nothing.
			#
			print("Seriously wanky difference here, got eat it.\n");
		    } elsif (0 
			     ||exists($diff_->{"c_R"})
			     ||exists($diff_->{"c_G"})
			     ||exists($diff_->{"c_B"})
			     ||exists($diff_->{"c_A"})){
			# if its any color element
			if ($alt_entry->{"c_R"} ) {
			    #
			}
		    }
		} elsif (! exists($diff_->{"Value"}) ) { # value is same, name or abbrev are not.
		    # If The value is different but name/abbrev/structure are the same
   		    if ($bogus_color[0] && $o_entry->{"Value"}==0){ #val same, but not 0
			# DELETE CURRENT
			#print("AUTO_RES: Current bogus\n");
			#remove_onto_line($o_entry->{"t_line"});
			#next; # and skip to next line
		    } elsif($bogus_color[1] && $alt_entry->{"Value"}==0 ){#val same, but not 0
			# DLETE ALT
			#print("AUTO_RES: Alt bogus\n");
			#remove_onto_line($alt_entry->{"t_line"});
			#$auto_res++;
		    } else {
			# COLOR NOT BOGUS, VALUE DIFFERENT ABBREV/NAME/STRUCTURE SAME
			# i dont think we have this caes, but just in case we do
			#push(@conflicts,$alt_entry->{"t_line"});
		    }
		}
		push(@conflicts,$alt_entry->{"t_line"});
		
		#display_diff($diff_);
		# dump(%$diff_);
		# display_complex_data_structure($diff_,"  ",0);#,'  ','pretty');
		# my @v = values(%{$diff_});
		# (s:(<):($1/t):) for @v;
		# my @k = keys(%{$diff_});
		# print($o_entry->{"t_line"}." ".$conflict." - \t(".join(") (",zip(@v,@k)).")\n");
		# print($o_entry->{"t_line"}." ".$conflict." - \t".join(" ",zip(@{values(%{$diff_})},@{keys(%{$diff_})}))."\n"); 
		# dump(@$diff_);
		
	    } else {
		# NO differing keys of interest
		#print("Strange DIFF result for $_ from and $conflict\n");
		print("No change in relevant keys... SO, check DIFF result for $o_entry->{t_line} from and $conflict\n");
		# we'll get this for exact same results.
		#dump($diff_);
	    }
	}
	print("fixed $auto_res with ".scalar(@conflicts)." remaining.\n") if (scalar(@conflicts)>0||$auto_res>0);
	if(scalar(@conflicts)>=1) {
	    my $temp_lineN=$o_entry->{"t_line"};
	    print("----$temp_lineN----\n");
	    display_complex_data_structure($o_table->{"t_line"}->{$temp_lineN});
	    print("--------\n");
	    
	    for $temp_lineN(@conflicts){
		print("----$temp_lineN----\n");
		display_complex_data_structure($o_table->{"t_line"}->{$temp_lineN});
		print("--------\n");
	    }
	    #my $best_line=get_user_response("Which of these conflicting numbers looks better?");
	    my $best_line;
	    if (length($best_line)>0){ # if we were given a better number, else leave them all.
		push(@conflicts,$o_entry->{"t_line"});
		while(scalar(@conflicts)>1){
		    my $temp_lineN=shift(@conflicts);
		    if ($best_line != $temp_lineN) {
			remove_onto_line($temp_lineN);
		    }
		}
	    }
	}
	#next;
	
	if( scalar(@error_fields)==1) {# there's only one error for this entry,
	    if ( $error_fields[0] eq "Abbrev" ) { # and its in the Abbreviation.
		# Then we can fix this, note these two steps MUST be peformed in this order.
		# First; 
		# Get first t_line.
		my $first_line_num=$seen->{"Abbrev"}->{$o_entry->{"Abbrev"}}[0];
		# MIGHT want to do the minimum t_line instead of just the first one found,
		# what with hashes not having guarnteed order and all. 
		my $first_entry=$o_table->{"t_line"}->{$first_line_num};
		# Fix the lookup table.
		$o_table->{"Abbrev"}->{$first_entry->{"Abbrev"}}=$first_entry;
		# Second;
		# Fix our personal entry, set abbreviation to name. 
		$o_entry->{"Abbrev"}=$o_entry->{"Name"};
		push(@onto_error_msgs,"\t ".$o_entry->{"t_line"}." Fixed by dumping the abbreviation");
		
	    } elsif ( $error_fields[0] eq "Value" ) { # and its in the Abbreviation.
	    }
	} else {
    	}
	
	my @parts=sort(keys %$o_entry); # get all the info types for this structure sorted.
	#my @parts=@o_columns;
	@parts=grep {/^Level_[0-9]+$/} @parts; # pair that down to only different ontology levels.
	#my @levels=@parts;
	my %l_p;# level preference holder for all the meta_structures for this link in ontology.
	if (scalar(@parts)>0 ) {# with re-tooling of spreadsheet load, this should always have the same number of entries as colums
	    my $potential_p=scalar(@parts); # potential parts.
	    #dump(%$o_entry); # this works.
	    #use Data::Dumper;
	    #print Dumper($o_entry);
	    #dump(%{$o_entry{@parts}}); # his doesnt.
	    #dump(%{$o_entry}); this works
	    #dump(@{$o_entry}{@parts});# THIS WORKS!!!!
	    #dump($o_entry->{@parts});# this is undef
	    #dump(@$o_entry->{@parts});# not an array reference
	    #dump(@$o_entry{@parts});# THIS WORKS!
	    #dump(@parts);
	    #
	    # get the defined levels of this structure
	    #
	    # "new" way use hash slice, but throws errors for undefined entries, and there will be undefined entries.
	    # "old way for each possible entry, if the entries are defined, add one at a time to array, and l_p hash.
	    if ( 0 ) {
		@l_p{@{$o_entry}{@parts}}=@parts;# has to be done first since we destroy parts next.
		@parts=@{$o_entry}{@parts};      # Now get the values at each present level. Generates errors for any missing levels. Be nice to fix that.
	    } else {
		my @np=();
		foreach(@parts){
		    #if ( defined  $o_entry->{$_} ){
		    if (exists $o_entry->{$_} && defined  $o_entry->{$_} ) {
			$l_p{$o_entry->{$_}}=$_;
			push(@np,$o_entry->{$_});
		    }
		}
		@parts=@np;
	    }
	    #dump(@parts);
	    #dump(\%l_p);
	    #die;
	    #IF there is only one part, AND its bogus!
	    if ( scalar(@parts)==1 ) {
		if (  ( not defined $parts[0] ) 
		      || ( $parts[0] eq '' ) 
		      || ( $parts[0] =~ /^\s*$/ )
		      || ( $parts[0] eq '0' )
		      || ( $parts[0] eq 'NULL' )
		      || ( $parts[0] eq 'UNSORTED' )  
		    ) {
		    warn("ASSIGNING UNSORTED DUE TO EMPTY/NULL BITS");
		    @parts=("UNSORTED");# at a minimum, they have unsorted....
		    %l_p={};
		    $l_p{"UNSORTED"}="Level_1";
		}
	    }
	    print("\t got ".scalar(@parts)." of ".$potential_p." levels\n") if $debug_val>=45;
	} else {
	    warn("NO Proper keys for line $o_entry->{t_line} using UNSORTED");
	    @parts=("UNSORTED");# at a minimum, they have unsorted....
	    %l_p={};
	    $l_p{"UNSORTED"}="Level_1";
	    sleep_with_countdown(2);
	}

	#
	# Get ontology levels and assign structure to the different levels in the ultra meta hash.
	#
	my @onto_levels=();my $level_show_bool=0;
	print($o_entry->{"Name"}."\t Line:".$o_entry->{"t_line"}."\n");
	for(my $pn=0;$pn<=$#parts;$pn++){
	    # process the different levels of ontology, get the different ontology names.
	    # clean them up and put them into the onto_levels list.
	    my $branch_name=$parts[$pn]; # meta structure name
	    if (! defined $branch_name ){
		# we dont have this level if its undefined.
		# this should no longer be possible.
		#die ("undef branch $pn");
		next;
	    }
	    trim($branch_name);
	    my $level_name=$l_p{$branch_name};#
	    my $tnum="";
	    ($tnum,$branch_name)= $branch_name =~/^([0-9]+_)?(.*)$/;
	    $tnum="" unless defined $tnum;
	    #$branch_name=~ s/[,\/#]/_/xg;#clean structure name of dirty elements replaceing them for underscores.
	    $branch_name=~ s/[,\/# ]/_and_/xg;#clean structure name of dirty elements replacing them with _and_.
	    $branch_name=~ s/[-\/# ]/_to_/xg;#clean structure name of dirty elements replacing them with _to_.
	    if ( ( 0 )
		 # THIS IS NOT DEACTIVATING THIS CODE, THIS IS FOR READABILITY LINEING THE CONDITIONS UP ON SUBSEQUENT LINES.
		 || ( not defined $branch_name ) 
		 || ( $branch_name eq '' ) 
		 || ( $branch_name =~ /^\s*$/ )
		 || ( $branch_name eq '0' ) 
		) {
		$level_show_bool=1;
		warn("bad tree name, skipping to next level");
		sleep_with_countdown(1);
		next; 
	    }
	    if ( ( $branch_name =~ /_to_/x )
		 || ($branch_name =~/_and_/x) ){
		if ( ( $branch_name =~ /_to_/x )
		     && ($branch_name =~/_and_/x) ) {
		    die("WOW Really trying to get me arnt you! ontology_line:$o_entry->{t_line}.");
		}
		# This is to split up entries with multiple pieces in the same cell.
		# eg, BrainPart_left_and_BrainPart_right
		# or, BrainPart1_to_BrainPart4
		# Support is rudimentary, because it gets tough to decipher additional peices.
		my @b_parts=split("_and_",$branch_name);
		# foreach b_part convert _ to space, and then trim to clean up erroneous underscores.
		my @tmp=();
		# THIS ALL FEELS SO CLUNKY, THERE MUST BE A MORE PERLY, CLEVER WAY
		while ( my $b_and =shift(@b_parts)) {
		    #these three goofy lines removes leading/trailing undescores
		    $b_and=~ s/_/ /xg;
		    trim($b_and);
		    $b_and=~ s/[ ]/_/xg;
		    my @b_endpoints=split("_to_",$b_and);
		    # can we operate on all array elements at once. No we cant.
		    if ( scalar(@b_endpoints)>2 ) {
			die ("Bad range! more than two endpoints");
		    }
		    my @range=();
		    my $bname;
		    use Scalar::Util qw(looks_like_number);
		    for(my $be=0;$be<=$#b_endpoints;$be++){
			# convert underscore to spaces, then trim to remove any leading/trailling spaces.
			$b_endpoints[$be]=~ s/_/ /xg;
			trim($b_endpoints[$be]);
			#my ($base,$num) = $b_endpoints[$be] =~ /^(.*?)([0-9]+)$/x;
			my ($base,$num) = $b_endpoints[$be] =~ /^([^0-9]+)(.*)$/x;
			if ( looks_like_number($num) ) {
			    push(@range,$num);
			} else {
			    push(@range,-1);
			}
			if ( defined $base ) { $bname=$base;} else { 
			    die("range error ontology line:".$o_entry->{"t_line"}."\n");}
		    }
		    $bname=~s/[ ]/_/xg;# convert sapces back to underscores
		    for(my $v=$range[0];$v<=$range[$#range];$v++){
			if ( $v>0 ){
			    push(@tmp,sprintf("%s%i",$bname,$v));
			} else {
			    push(@tmp,$bname);
			}
		    }
		}
		push(@onto_levels,@tmp);
		# foreach onto_level add tnum to the tnum lookup
		for my $ol (@tmp) {
		    if ( ! exists($onto_hash->{"order_lookup"}->{$ol} ) ){
			if( $tnum ne "" ) {
			    $onto_hash->{"order_lookup"}->{$ol}=$tnum;
			} else {
			    $onto_hash->{"order_lookup"}->{$ol}="1_";
			}
		    }
		    if ( ! exists($onto_hash->{"LevelAssignments"}->{$ol}->{$level_name}) ){
			$onto_hash->{"LevelAssignments"}->{$ol}->{$level_name}=1;
		    } else {
			$onto_hash->{"LevelAssignments"}->{$ol}->{$level_name}=$onto_hash->{"LevelAssignments"}->{$ol}->{$level_name}+1;
		    }
		}
	    } else {
		if (0 && $o_entry->{"t_line"}==51 ){ # line 51 was a multi_line in the past, that'll probably change.
		    print($o_entry->{"Name"}.": tnum=$tnum,branch_name=$branch_name\n");
		}
		# foreach onto_level add tnum to the tnum lookup
		push(@onto_levels,$branch_name);
		if ( ! exists($onto_hash->{"order_lookup"}->{$branch_name} ) ){
		    if( $tnum ne "" ) {
			$onto_hash->{"order_lookup"}->{$branch_name}=$tnum;
		    } else {
			$onto_hash->{"order_lookup"}->{$branch_name}="1_";
		    }
		} else {
		    printd(95,"Using order lookup for $branch_name\n");
		    my $a_tnum=$onto_hash->{"order_lookup"}->{$branch_name};
		    if ($a_tnum ne $tnum 
			&& $tnum ne "" 
			&& $debug_val>=45) {
			print("AttemptedLevelOverride!".$o_entry->{"Name"}.
			      ": branch_name=$branch_name tnum=\"$a_tnum\" is not \"$tnum\"\n");
		    }
		}
		if ( ! exists($onto_hash->{"LevelAssignments"}->{$branch_name}->{$level_name}) ){
		    $onto_hash->{"LevelAssignments"}->{$branch_name}->{$level_name}=1;
		} else {
		    $onto_hash->{"LevelAssignments"}->{$branch_name}->{$level_name} =
			$onto_hash->{"LevelAssignments"}->{$branch_name}->{$level_name}+1;
		}
	    }
	    if  ( 0 
		  && $branch_name =~ /^[rmp][0-9]{1,2}(?:[^\w]+[\w]*)?$/x) {
		warn("\tAlex said to skip these structures($branch_name)");
		next;
	    }
	}

	# HERE WE SHOULD BE ABLE TO SEE PARTS
	# dump(@onto_levels);
	#sleep_with_countdown(15);
	@onto_levels=uniq(@onto_levels);
	printf("\t".join("\n\t",@onto_levels)."\n") if ($debug_val>45);
	# onto_hash will have at least 4 parts.
	# onto superstructures, branches with many leaves
	# onto lines to superstructs, leaves with all possible branches.
	foreach (@onto_levels){
	    #print($o_entry->{"Name"}."\t".0."\n");
	    push(@{$onto_hash->{"SuperStructures"}->{$_}},$o_entry->{"t_line"});
	}
	@{$onto_hash->{"line_to_struct"}->{$o_entry->{"t_line"}}}=@onto_levels;
	# onto super_nums, the superstructures with their number if they've got one. Only the first number found will be use. 
	# onto branches, once we have the other two components we'll try to back calculate the ontology lookup.
    }

    #dump($onto_hash->{"LevelAssignments"});die;
    #dump($seen);die;
    if( scalar(@onto_error_msgs) ) {
	warn (join("\n",@onto_error_msgs));
    }
    #dump(@onto_errors);
    #die;
    #dump($onto_hash);
    #die;
    # NOW WE NEED TO RE_CREATE THE BRANCHES.
    # What order of operations should we use here....
    # foreach line,
    #dump($onto_hash->{"line_to_struct"});
    #    sort supers by their content count. Arrange largest to smallest, That is a good approximation of correct.
    # MAYBE we should look deeper, but lets not bother at first.

    #
    # construct the super structure hash of superstructure=>leaf_count
    #
    my $super_struct_hash;
    my @super_structs=keys(%{$onto_hash->{"SuperStructures"}});
    #dump($onto_hash->{"SuperStructures"});
    dump($onto_hash->{"LevelAssignments"});
    for my $super (@super_structs) {
	if ( ! exists($onto_hash->{"SuperStructures"}->{$super} ) ) {
	    print("Missing $super\n");
	}
	$super_struct_hash->{$super}=scalar(@{$onto_hash->{"SuperStructures"}->{$super}}); # this isnt right.?

	my $max=0;
	my $level=0;
	#dump($onto_hash->{"LevelAssignments"}->{$super});exit;
	#printd(95,"Getting best level of $super  ");
	foreach ( sort(keys(%{$onto_hash->{"LevelAssignments"}->{$super}} )) ) {
	    my $t=$onto_hash->{"LevelAssignments"}->{$super}->{$_};
	    if( $t>$max){
		#printd(95,"New max $_ \n");
		$max=$onto_hash->{"LevelAssignments"}->{$super}->{$_};
		($level)=$_=~/Level_([0-9]+)/x;
	    }
	}
	$onto_hash->{"LevelPreference"}->{$super}=$level;
	#printd(95,"found $level\n");
    }
    $onto_hash->{"SuperCount"}=$super_struct_hash;
    #dump($onto_hash->{"LevelPreference"});
    #dump($onto_hash->{"SuperCount"});
    #exit;
    
    #
    # sort keys of super hash descending by count of leaf structures.
    # And by level preference, so we can use equiv parentage.
    #
    if ( 1 ) { 
	@super_structs = sort { $onto_hash->{"SuperCount"}->{$b} <=> 
				$onto_hash->{"SuperCount"}->{$a} 
			    || $onto_hash->{"LevelPreference"}->{$a} <=> 
				$onto_hash->{"LevelPreference"}->{$b} 
			    
	} keys(%{$onto_hash->{"SuperCount"}});
	#dump(@super_structs);
    } else {
	# sort first by level preference
	@super_structs = sort { $onto_hash->{"LevelPreference"}->{$a} <=> 
				    $onto_hash->{"LevelPreference"}->{$b} 
	} keys(%{$onto_hash->{"LevelPreference"}});
	dump(@super_structs);
	# then add sort by super count. This preserves older sorting so we can progressivly add more things, if that becomes a ndeed. This code is just a vestigal example.
	@super_structs = sort { $onto_hash->{"SuperCount"}->{$b} <=> 
				    $onto_hash->{"SuperCount"}->{$a} 
	#} keys(%{$onto_hash->{"SuperCount"}});
	} @super_structs;
	dump(@super_structs);
	
    }
    #dump($onto_hash);
    #dump(@super_structs);
    #printd(5,"Temporary EXIT, need to insert code which trys to sort by level right here\n");
    #exit;
    
    my @potential_parents=();
    #dump($onto_hash);
    #sleep_with_countdown(15);

    
    #
    # For every "branch" assume its a twig, and find potential parents.
    #
    # Potential parents must have more entries to them. SO, since we're sorted, 
    # we can safely assume previous "twigs" are potetntial parents, and then evaluate from there.
    # 
    # This should allow us to check each previous one in turn, adding to the ontology in pieces.
    # Even furhter, we should check previous parents in reverse as we want the smallest match possible.
    #
    # This has a problem when you parents have exactly the same assignment count. Which can occur.
    $onto_hash->{"Hierarchy"}={};
    print("Lineage Discovery\n");
    my $black_list={}; # Second pass structures.
    my @orphans=();
    while(my $twig=shift(@super_structs) ){
	$onto_hash->{"Branches"}->{$twig}={};
	#dump(@potential_parents);
	my $t_c=$onto_hash->{"SuperCount"}->{$twig};
	print("  $twig:$t_c\n") if ($debug_val>40);
	foreach my $pp (reverse(@potential_parents)) {
	    #reverse to let us check the next biggest parent.
	    # get parent element count
	    my $p_c=$onto_hash->{"SuperCount"}->{$pp};
	    if ($p_c>=$t_c){
		print("\t$p_c <= $pp\n") if ($debug_val>40);
		# if elementcount of child < elementcount of parent
		#   get parent elements
		my @p_e=@{$onto_hash->{"SuperStructures"}->{$pp}};
		#   join parents into sorted string
		my $par_leaves=join("_",sort(@p_e));
		#   get child elements
		my @t_e=@{$onto_hash->{"SuperStructures"}->{$twig}};
		#   join children into regex 
		#my $child_reg=join("(_.*_)|(_)",sort(@t_e)); # this was wrong, it mached ANY single.
		#my $child_reg="(^|_)".join("(_|([0-9]+_)+)",sort(@t_e))."($|_)";
		#my $child_reg='(^|_)'.join('(_|(_[0-9]+_)+)',sort(@t_e)).'($|_)';# I THNK this child_reg almost does it. Probably need to do slightly better.
		#my $child_reg=join('(_|(_[0-9]+_)+?)',sort(@t_e));
		
		# check if we're the same category of structure eg,  m, p, r
		my ($pname,$pnum)=$pp=~ /^([^0-9]+)(.*)$/x ;
		my ($tname,$tnum)=$twig=~ /^([^0-9]+)(.*)$/x ;
		if ( $tname eq $pname ) {
		    print("BAM TOO SIMILAR\n") if ($debug_val>40);
		    next;
		}
		#   do our compare.
		#if ( $par_leaves=~/$child_reg/x ){
		my $child_match=1;
		while(my $num= shift(@t_e) ) {
		    my $regx='(^|_)'.$num.'($|_)';
		    if ($par_leaves !~ /$regx/x) {
			$child_match=0;
			last;
		    }
		}
		if ( $child_match ) {
		    print("Best parent of $twig is $pp\n") if ($debug_val>=45);
		    # add to hash....
		    #if ( ! exists($onto_hash->{"Twigs"}->{$pp}) && exists($onto_hash->{"Branches"}->{$pp}) ) {
		    #$onto_hash->{"Hierarchy"}=$onto_hash->{"Branches"}->{$pp};
		    #}
		    if (    ! exists($onto_hash->{"Twigs"}->{$pp}) 
			 && ! exists($onto_hash->{"Hierarchy"}->{$pp})
			 &&   exists($onto_hash->{"Branches"}->{$pp})  ) {
			print("Additional root $pp\n");
			$onto_hash->{"Hierarchy"}->{$pp}=$onto_hash->{"Branches"}->{$pp};
		    }
		    if ( ! exists($onto_hash->{"Branches"}->{$pp}->{$twig} ) ){
			$onto_hash->{"Branches"}->{$pp}->{$twig}=$onto_hash->{"Branches"}->{$twig};
			#if ( exists $onto_hash->{"Twigs"}->{$twig}->{$pp} ) {
			if ( exists($onto_hash->{"Twigs"}->{$twig}) ) {
			    warn("Twig already has parent");
			}
			$onto_hash->{"Twigs"}->{$twig}->{$pp}=$pp;#$onto_hash->{"Branches"}->{$pp};
		    }
		    last;
		}
		#if ( scalar(@t_e)>60) {exit;}
	    }
	}
	push(@potential_parents,$twig);
    }
    # Do another pass, to catch any missing parent nodes.
    if ($#super_structs>=0 ){
	die("ERROR: PROCESSING INCOMPLETE");
    }
    @super_structs=keys(%{$onto_hash->{"SuperCount"}});
    while(my $twig=shift(@super_structs) ){
	if (    ! exists($onto_hash->{"Twigs"}->{$twig}) 
		&& ! exists($onto_hash->{"Hierarchy"}->{$twig})
		&&   exists($onto_hash->{"Branches"}->{$twig})  ) {
	    print("Additional root $twig\n");
	    $onto_hash->{"Hierarchy"}->{$twig}=$onto_hash->{"Branches"}->{$twig};
	}
    }
    
    #dump($black_list);
    #dump(@orphans);
    #dump(%{$onto_hash->{"Branches"}});
    #dump(%{$onto_hash->{"Hierarchy"}});exit;
    #dump(%{$onto_hash->{"Twigs"}});
    #exit;
    #Data->Dumper($onto_hash->{"Branches"});
    #use Data::Dumper;
    #Data::Dumper($onto_hash->{"Branches"});
    #display_complex_data_structure($onto_hash->{"Branches"});
    display_complex_data_structure($onto_hash->{"Hierarchy"});
    #display_complex_data_structure($onto_hash->{"Twigs"});
    #exit;
    #
    # Loop over all lines, pull out ontology levels
    #
    if(0){foreach (keys( %{$o_table->{"t_line"}}) ) {
    	#dump($_);
	#dump(ref $_);
	my $o_entry=$o_table->{"t_line"}->{$_};
	my @parts=sort(keys %$o_entry); # get all the info types for this structure sorted.
	#my @parts=@o_columns;
	@parts=grep {/^Level_[0-9]+$/} @parts; # pair that down to only different ontology levels.
	for(my $pn=0;$pn<=$#parts;$pn++){
	    # process the different levels of ontology, get the different ontology names.
	    my $branch_name=$parts[$pn]; # meta structure name
	    trim($branch_name);
	    my $tnum="";
	    ($tnum,$branch_name)= $branch_name =~/^([0-9]*_)?(.*)$/;
	    $tnum="" unless defined $tnum;
	    $parts[$pn]=$branch_name;
	}
	@parts=reverse(@parts);
    }}
    #
    # Update ontology_table
    #
    # adding direct assignments array for branches which have valid twigs.
    # so we know which twigs a leaf belongs to in the main code.
    my $max_levels=1;
    my $err_stop=0;
    foreach (keys( %{$o_table->{"t_line"}}) ) {
	my $o_entry=$o_table->{"t_line"}->{$_};
	#    for each superstructure of the line,
	@super_structs=@{$onto_hash->{"line_to_struct"}->{$o_entry->{"t_line"}}};# reusing var from above.
	# sort keys by value, descending (use a,b for ascending, or b,a for descending).
	#my %h; $h{"test2"}=1; $h{"test1"}=60; $h{"test3"}=30; 
	#my @h_keys = sort { $h{$a} <=> $h{$b} } keys(%h);
	#dump(keys(%h));
	##("test1", "test3", "test2")
	#dump(@h_keys);
	##("test2", "test3", "test1")
	#dump(@super_structs);
	@super_structs = sort { $onto_hash->{"SuperCount"}->{$b} <=> $onto_hash->{"SuperCount"}->{$a} } @super_structs;



	# 
	# update current ontology entry with the correct level count.
	#
	# need to refactor this to make up a min level arrangement.i
    if ( 1 ) {
	# We're gonna make a hash of levels for this structure, then add it back to the ontology.
	# super_structs is currently a descending list of the structures we're a part of.
	my $l_hash={};
	# so, for each super structure, 
	for my $super (@super_structs) {
	    #we should get their ancestor count. That is their level.
	    my $super_level=1;
	    my $par=$super;
	    while(exists($onto_hash->{"Twigs"}->{$par}) ) {
		($par)=keys(%{$onto_hash->{"Twigs"}->{$par}});
		$super_level++;
	    }
	    my $l_name=sprintf("Level_%i",$super_level);
	    printf("%s -> %s\n",$super,$l_name);
	    # here we can vote for our result superlevel
	    push(@{$l_hash->{$l_name}},$super);
	    if(exists($onto_hash->{"SuperLevel"}->{$super}->{$l_name}) ) {
		$onto_hash->{"SuperLevel"}->{$super}->{$l_name}++;
	    } else {
		$onto_hash->{"SuperLevel"}->{$super}->{"Name"}=$super;
		$onto_hash->{"SuperLevel"}->{$super}->{$l_name}=1;
	    }
	}
	#dump($o_entry->{"Name"});
	#dump($l_hash);
	#exit;
	my $cur_depth=scalar(keys %{$l_hash});
	if($max_levels<$cur_depth) {
	    $max_levels=$cur_depth;
	}
	for(my $ln=1;$ln<=$cur_depth||exists($o_entry->{sprintf("Level_%i",$ln)});$ln++){
	    #if(exists($o_entry->{sprintf("Level_%i",$ln+1)}) ) {
	    my $level_string=sprintf("Level_%i",$ln);
	    if ($ln>$cur_depth) {
		#print($o_entry->{"Name"}.": KILL LEVEL $level_string\n") if ($debug_val>=45);
		print($o_entry->{"Name"}.": Remove $level_string\n") if ($debug_val>=45);
		delete $o_entry->{$level_string};
	    } else {
		#$o_entry->{$level_string}=$onto_hash->{"order_lookup"}->{$super_structs[$ln-1]}.$super_structs[$ln-1];
		if ( exists ( $l_hash->{$level_string} ) ) {
		    $o_entry->{$level_string}=join(",",@{$l_hash->{$level_string}});
		} else {
		    die("BOOM BADHASH $level_string");
		}
		
		#$onto_hash->{"order_lookup"}->{$super_structs[$ln-1]}.$super_structs[$ln-1];
	    }
	}
	#dump($o_entry);
	#exit;
        } else {
	#
	# BEGIN INACTIVE CODE
	#
	# need to refactor this to make up a min level arrangement.
	if($max_levels<scalar(@super_structs)){
	    $max_levels=scalar(@super_structs);
	}
	for(my $ln=1;$ln<=scalar(@super_structs)||exists($o_entry->{sprintf("Level_%i",$ln)});$ln++){
	    #if(exists($o_entry->{sprintf("Level_%i",$ln+1)}) ) {
	    my $level_string=sprintf("Level_%i",$ln);
	    if ($ln>scalar(@super_structs)) {
		print($o_entry->{"Name"}.": KILL LEVEL $level_string\n") if ($debug_val>=45);
		delete $o_entry->{$level_string};
	    } else {
		$o_entry->{$level_string}=$onto_hash->{"order_lookup"}->{$super_structs[$ln-1]}.$super_structs[$ln-1];
	    }
	}
	#
	# END INACTIVE CODE
	#
        }

	#
	# make direct assignment list for this structure.
	#
	# this clears super_structs, and selectively adds to direct_assignments.
	# looks like this may fail when there's only one assignment.
	printd(50,"\tSetting direct assignments for ".scalar(@super_structs)." structure(s).\n");
	my @direct_assignments;
	for(my $s_c=0;$s_c<=$#super_structs;$s_c++){
	    my $cur=shift(@super_structs);
	    my $found_on_branch=0;
	    #print("Test cur $cur\n");
	    for my $test_struct (@super_structs){
		if ( exists($onto_hash->{"Branches"}->{$cur}->{$test_struct}) ){
		    print("Found $test_struct as part of $cur\n") if ($debug_val>40);
		    $found_on_branch=1;
		    last;
		}
	    }
	    if ( ! $found_on_branch ) {
		push(@direct_assignments,$cur);
	    }
	    push(@super_structs,$cur);# Add tested struct to end of list
	}
	
	#
	# Check that at least one structure will be directly assigned. This code should never run.
	#
	printd(50,"\tEnsuring assignment of structure ( $o_entry->{Name} ) at least one place.\n");
	my $err_t="";
	if( ! scalar(@direct_assignments) ) {
	    if ($o_entry->{"Name"} !~ /^Exterior|Inside$/x ) {
		$err_stop=1;
	    }
	    $err_t="Err Line: ".$o_entry->{"t_line"}." ".join(",",@super_structs).")";
	    my $t_hash;
	    for my $structure(@super_structs) {
		$t_hash->{$structure}=$onto_hash->{"Branches"}->{$structure};
	    }
	    dump(@super_structs);
	    display_complex_data_structure($t_hash);
	}
	#local $debug_val=40;
	if ( $debug_val>=25){
	    printf("%s %i/%i ( %s)%s.\n",
		   $o_entry->{"Name"},
		   scalar(@direct_assignments),scalar(@super_structs),
		   join(",",@direct_assignments),
		   $err_t);
	}
	if( scalar(@direct_assignments) > 0 ) {
	    $o_entry->{"DirectAssignment"}=\@direct_assignments;

	} else {
	    print("HANGING STRUCTURE\n");
	    dump($o_entry);
	    my $msg="No assignments made for ($o_entry->{Name}), REMOVME THIS FROM YOUR LISTS!";
	    cluck($msg);
	    sleep_with_countdown(4);
	}
	#dump($o_entry);
    }
    if ($err_stop){
	die("Error understanding ontology table, see above.");
    }
    
    #
    # Re-write header of o_table.
    #
    my $ln=1;
    while(exists($o_table->{'Header'}->{sprintf("Level_%i",$ln)}) ){
	delete($o_table->{'Header'}->{sprintf("Level_%i",$ln)});
	$ln++;
    }
    my $field_count=0;
    my @sorted_order = sort { $o_table->{'Header'}->{$a} <=> $o_table->{'Header'}->{$b} } keys(%{$o_table->{'Header'}});
    $field_count=$#sorted_order;
    @{$o_table->{'Header'}}{@sorted_order}=(0 .. $field_count); # assigns new ording to existing columns from 1 to field count.
    
    for($ln=1;$ln<=$max_levels;$ln++){
	$o_table->{'Header'}->{sprintf("Level_%i",$ln)}=$ln+$field_count;
    }
    #
    # Add header entry to the superlevel structure.
    #
    #dump $onto_hash->{"SuperLevel"};
    $field_count=0;
    $onto_hash->{"SuperLevel"}->{"Header"}->{"Name"}=0;
    for($ln=1;$ln<=$max_levels;$ln++){
	$onto_hash->{"SuperLevel"}->{'Header'}->{sprintf("Level_%i",$ln)}=$ln+$field_count;
    }
    #dump($onto_hash->{"SuperLevel"}->{"Header"});exit;
    #exit;
    return $onto_hash;
}

sub compare_onto_lines {
    # compares two hashes and an optional ignore list, returning a hash of the differing keys, or [<|>]key  for missing keys 
    my ($L_1, $L_2,@ignore_list)=@_;

    
    my @comp_keys=uniq((keys(%{$L_1}),keys(%{$L_2})));
    my %ignore;
    if(scalar(@ignore_list)){ #if has elements.
	#print("Ignoring Some.. ");
	#sleep_with_countdown(5);
	@ignore{@ignore_list}=();
    }
    my $diff_={};# my $differing_keys=[];
    foreach (@comp_keys){
	if ( ! exists($ignore{$_} ) ){# if not an ignore key
	    # cases, exist, undef, 
	    # all conditions true.
	    if ( exists($L_1->{$_}) && exists($L_2->{$_})
		 && defined $L_1->{$_} && defined $L_2->{$_} ) {
		    if ( $L_1->{$_} ne $L_2->{$_} ){
			$diff_->{$_}='|';
		    } else {
			#$diff_->{$_}='=';#push(@{$differing_keys},$_);		    
		    }
		
		
	    } elsif ( exists($L_1->{$_}) ) {
		if ( defined $L_1->{$_}) {
		    $diff_->{$_}='<';
		}
	    } elsif ( exists($L_2->{$_}) ) {
		if ( defined $L_2->{$_}) {
		    $diff_->{$_}='>';
		}
	    } else {
	    }
	}
    }
    return $diff_; #return $differing_keys;
}

sub display_diff {
    my ($diff_)=@_;
    foreach (sort(keys %{$diff_})){
	# three parts to a display line,
	# part 1 is either the key or an indent
	# part 2 is the value
	# part 3 is either they key or nothing.
	my @parts;
	if ( $diff_->{$_} eq '>' ) {
	    @parts=("\t",$diff_->{$_},$_);
	#} elsif( $diff_->{$_} eq '<' ) {
	    #@parts=($_,$diff_->{$_});
	} else {
	    @parts=($_,"\t".$diff_->{$_});
	}
	print(join(" ",@parts)."\n");
    }
    return;
}

sub remove_onto_line {
    my ($o_table,$line_num)=@_;
    #dump($o_table);exit;
    if (! exists($o_table->{"t_line"}->{$line_num}) ) {
	print("missing: $line_num!\n");
	return;
    } else {
	print("REMOVING: $line_num!\n");
	#sleep_with_countdown(2);
    }
    my $hash_=$o_table->{"t_line"}->{$line_num};
    my @kv=keys(%{$hash_});
    foreach (@kv) {
	if (exists ( $o_table->{$_}->{$_}) 
	    &&  $o_table->{$_}->{$_} eq $hash_ ){
	    print("Will remove $_ : $hash_->{$_}");
	    #delete $o_table->{$_}->{$_}; # remove current line
	}
    }
    delete $o_table->{"t_line"}->{$hash_->{"t_line"}}; # remove current line
    return; 
}

sub prompt_example {
    print "Can you read this? ";
    my $answer = <STDIN>;
    if ($answer =~ /^y(?:es)?$/i)
    {
	print "Excellent\n";
    }
    else
    {
	print "Then how did you answer?\n";
    }
}

sub get_user_response {
    my($msg)=@_;
    print "$msg";
    my $answer = <STDIN>;
    chomp($answer);
    return $answer;
    if ( 0 ) {
    if ($answer =~ /^y(?:es)?$/i) {
	print "Excellent\n";
    } else {
	print "Then how did you answer?\n";
    }}
    
}
exit;
