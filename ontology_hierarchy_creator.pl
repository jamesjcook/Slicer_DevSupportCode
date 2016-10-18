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
if (! getopts('c:h:m:o:t:', \%opt||$#ARGV>=0)) {
    die "$!: Option error, valid options, -h hierarchy.csv -m input_mrml.mrml -c colortable.txt (-o output.mrml)? (-t (clean|Abbrev|modelfile|ontology))?";
}
#-h hierarchy.csv
#-m inmrml.mrml
#-c colortabl.txt
#-o output.mrml

#my $ontology_inpath=$ARGV[0];
my $p_ontology_in=$opt{"h"};#$opt{""};
#my $p_mrml_in=$ARGV[1];
my $p_mrml_in=$opt{"m"};
#my $p_mrml_out=$ARGV[2];
my $p_mrml_out=$opt{"o"};
#my $rename_type=$ARGV[3];
my $rename_type=$opt{"t"};
my $p_color_table_in=$opt{"c"};
my $model_prefix="Model_";
$debug_val=25;
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
if ( ! defined $p_mrml_out ) {
    my ($p,$n,$e)=fileparts($p_mrml_in,2);
    #print "n=$n p=$p e=$e\n";
    $p_mrml_out=$p.$n."_".$rename_type."_out".$e;
    print("Auto mrml out will be \"$p_mrml_out\".\n") ;
}

my ($Tp,$Tn,$Te)=fileparts($p_color_table_in,2);
my $p_color_table_out=$Tp.$Tn."_".$rename_type."_out".$Te;

($Tp,$Tn,$Te)=fileparts($p_ontology_in,2);
my $p_ontology_out=$Tp.$Tn."_".$rename_type."_out".$Te;
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
$splitter->{"Input"}=[qw(Name Structure)];# reformulate this var, keeping original in other
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
my ($d_abr,$d_nam,$d_str)=(0,0,0);
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
if ($d_abr||$d_nam||$d_str){
    $Tr=$c_table->{"t_line"};
    printf("%i\n",scalar(keys %{$c_table->{"t_line"}}));
    printf("%i\n",scalar(keys %$c_table));
}
	#exit;
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


my $ontology=cleanup_ontology_levels($o_table);



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
printf("Final ontology line number =$ONTOLOGY_INSERTION_LINE\n");

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
if ( 1 ) {
    # The other code was set aside beacause we cant rely on it being the first node.
    # so, we'll get the first node, if that node has a parentNodeRef, we'll follow it until we find a node without a parent.
    my @vtkMRMLHierarchyNodes=mrml_attr_search($mrml_data,"id",$rootHierarchyNodeID,"ModelHierarchy");
    # I think this'll find two nodes, One ModelHierarchy directly attahced to the MRML section of the hash,
    # and another directly attached to SceneView, which is attached to MRML. As far as i can tell these are the same.
    # There is just an inherrent inefficiency in the way slicer stores its information.
    if (  $#vtkMRMLHierarchyNodes<0 ) {#there is at least one node.
	die("No root MRML nodes!!!!");
    }

    my $rootHierarchyNode=$vtkMRMLHierarchyNodes[0];
    # while the current root has a parent, its not really the root... so we should get its parent.
    while (exists ($rootHierarchyNode->{"parentNodeRef"}) ) { 
	my @parent_candidates=mrml_find_by_id($mrml_data,$rootHierarchyNode->{"parentNodeRef"}); # could i just scalar that for how i'm doing things?
	$rootHierarchyNode=$parent_candidates[0];
    }
    if ( ! defined $rootHierarchyNode->{"id"} ) {
	dump(@vtkMRMLHierarchyNodes);die("Couldnt find node");
    } else {
	print("root is ".$rootHierarchyNode->{"id"}."\n");
	#exit;
    }
    $rootHierarchyNodeID=$rootHierarchyNode->{"id"};
    #$rootHierarchyNode=$vtkMRMLHierarchyNodes[0];
    #print("Found ".scalar @vtkMRMLHierarchyNodes." Hierarchy root(s).\n");
    
} else {

    $rootHierarchyNodeID="vtkMRMLModelHierarchyNode1";
    my @vtkMRMLHierarchyNodes=mrml_attr_search($mrml_data,"id",$rootHierarchyNodeID."\$","ModelHierarchy");
    # I think this'll find two nodes, One ModelHierarchy directly attahced to the MRML section of the hash,
    # and another directly attached to SceneView, which is attached to MRML. As far as i can tell these are the same.
    # There is just an inherrent inefficiency in the way slicer stores its information.
    #$mrml_node->{"name"}
    if (  $#vtkMRMLHierarchyNodes>=0 ) {#there is at least one node.
	$rootHierarchyNode=$vtkMRMLHierarchyNodes[0];
	print("Found ".scalar @vtkMRMLHierarchyNodes." Hierarchy root(s).\n");
    } else {
	die("No root MRML nodes!!!!");
    }
}
#my $mrml_data=mrml_find_by_name($mrml_data->{"MRML"},"whiteSPCmatter","ModelHierarchy");
#my $mrml_data=mrml_find_by_name($mrml_data,"whiteSPCmatter","ModelHierarchy");
#my $mrml_data=mrml_find_by_name($mrml_data,"whiteSPCmatter");#,"ModelHierarchy");
#display_complex_data_structure($mrml_data,'  ','pretty');
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
$splitter->{"Input"}=[qw(Structure Structure)];# reformulate this var, keeping original in other
$splitter->{"Output"}=[qw(Value Structure Abbrev Name)];  # generating these four


#exit;
###
#foreach model in mrml_data
###
my @missing_model_messages;
my @found_via_ontology_color;
my $processed_nodes=0;
my $do_unsafe=0;
my %l_1;
my %onto_hash;
foreach my $mrml_model (@mrml_nodes) {
    # Names come from color_tables, so the names should follow a regular pattern here + the added slicer model gen bits.
    my %n_a; # a holder for the multiple lookup possibilities for each model. This is a multiple level hash cross ref of the names and all the values. 
    # model names are split into the component parts, given the splitter defined above.
    # the default splitter used for paxinos/alex(RBSC)'s labels shows lookup potentials of value, structure_full_avizo_name, Abbrev, Name.
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
	warn($msg." and couldnt recover");
	next;
    }

    #### NEED TO ENSURE THE n_a HASH IS CORRECT HERE.
    #
    # For poorly formed entries we can have unfilled or missing fields!
    # 
    
    
    ### 
    # get the color_table info by abbrev, or value, or Name
    ###
    # we sort throught the possible standard places it could be.
    # adding second chance via color lookup.
    my ($c_entry,$o_entry);
    my @c_test=qw(Abbrev Value Name Structure); # sets the test order, instead of just using the collection order of splitter->{'Output'}.
    my $tx;
    do {
	$tx=shift(@c_test) ;
    } while(defined $n_a{$tx} 
	    && ! exists ($c_table->{$tx}->{$n_a{$tx}} )
	    && $#c_test>0 );
    
    if( defined $n_a{$tx} && exists ($c_table->{$tx}->{$n_a{$tx}}) ) {
	$c_entry=$c_table->{$tx}->{$n_a{$tx}};
    } else {
	print("$mrml_name\n\tERROR, No color table Entry found!\n");
	push(@missing_model_messages,"No color table entry".$mrml_name);
	dump(%n_a);
    }
    ### 
    # get the ontology_table info by abbrev, or value, or Name
    ###
    # we sort throught the possible standard places it could be.
    # adding second chance via color lookup.
    my @o_test=qw(Abbrev Name Structure);  # sets the test order, instead of just using the collection order of splitter->{'Output'}.
    do {
	$tx=shift(@o_test) ;
    } while(defined $n_a{$tx} 
	    && ! exists ($o_table->{$tx}->{$n_a{$tx}} )
	    && $#o_test>0 );
    if( defined $n_a{$tx} && exists ($o_table->{$tx}->{$n_a{$tx}}) ) {
	$o_entry=$o_table->{$tx}->{$n_a{$tx}};
    } else {
	print("$mrml_name\n\tERROR, No ontology Entry found!\n");
	if ( 1 ) {
	    push(@missing_model_messages,"No ontology table entry: ".$mrml_name);
	    dump(%n_a);	
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
	if ( scalar(keys(%$c_entry)) > 2) {
	    print("FOUND C_ENTRY\n") if $debug_val>=35;
	    dump($c_entry) if $debug_val >= 35;
	    # ADD the o_entry to the o_table here!!!
	    # Hash_dupe!
	    # structure abbrev level_1 .. level_n c_r c_g c_b c_a
	    #	    $o_entry=
	    $o_entry=\%{clone $c_entry};
	    $o_entry->{"t_line"}=$ONTOLOGY_INSERTION_LINE;
	    $ONTOLOGY_INSERTION_LINE++;
	    #@$o_entry{keys %$c_entry}=$c_entry->{keys %$c_entry};
	    # now for each key in the o_table add a 0 to our o_entry, THEN add our o_entry to each point of the o_table.
	    my @o_columns=keys %{$o_table->{'Header'}};#keys %$o_table;
	    foreach (@o_columns) {
		if ( ! exists($o_entry->{$_} ) ) {
		    $o_entry->{$_}=0;
		}
	    }
	    #for my $col (@o_columns) {
	    my $col="t_line"; {
		if ( ! exists($o_table->{$col}->{$o_entry->{$col}} ) ) {
		    $o_table->{$col}->{$o_entry->{$col}}=$o_entry;
		    printf("Added o_entry to index $col at $o_entry->{$col}\n");
		    #sleep_with_countdown(2);
		} else {
		    printf("$col has entry for $o_entry->{$col}\n" ) ;
		}
		if ( ! exists($o_table->{$col}) ){ 
		    warn("o_table missing Index: $col\n");
		}
	    }
	    #dump($o_entry);
	}
	if ( scalar(keys(%$o_entry)) > 2) {
	    print("FOUND O_ENTRY\n") if $debug_val>=35;
	    dump($o_entry) if $debug_val>=35;
	    # ADD the c_entry to the c_table here!!! 
	}
	next;
    } else {
	$processed_nodes++;
	#dump($c_entry);
    }
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
       
    my $alt_name=$n_a{"Name"};
    #my $Abbrev=$n_a{"Abbrev"};
    my $Abbrev=$c_entry->{"Abbrev"};
    my $value=$c_entry->{"Value"};
    if (! defined ($alt_name) ) {
	$alt_name=$Abbrev;
	$n_a{"Name"}=$Abbrev;
    }
    #printf("n=%s,ab=%s,v=%i\n",$alt_name,$Abbrev,$value);
    #next;#ondebuging, just goto next
    
    #  while level_next exists, check for level, add it
    # grep {/Level_[0-9]+$/} keys %$o_entry;
    #dump($o_entry);
    print("Fetching levels for $alt_name") if $debug_val>=45;
    my @parts=sort(keys %$o_entry); # get all the info types for this structure sorted.
    @parts=grep {/Level_[0-9]+$/} @parts; # pair that down to only different ontology levels.
    if (scalar(@parts)>0 ) {
	print("\t got ".scalar(@parts)."\n") if $debug_val>=45;
	#dump(%$o_entry); # this works.
	#dump(%{$o_entry{@parts}}); # his doesnt.
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
    #  add wiring....?
    my $s_path='Static_Render/LabelModels';
    my $ref=\%onto_hash;
    my $parent_ref=$rootHierarchyNode;
    my @vtkMRMLModelDisplayNodes;
    print("Getting ready to processnode $alt_name\n");
    #print("dumping right now just forstesting\n");dump ($parent_ref); exit;
    #mrml_attr_search($mrml_data,"id",$parent_ref->{"displayNodeID"}."\$","ModelDisplay");# this may not be what i'm looking to do.
    if ( defined ($parent_ref->{"displayNodeID"} ) ) {
	@vtkMRMLModelDisplayNodes=mrml_attr_search( $mrml_data,"id",$parent_ref->{"displayNodeID"}."\$","ModelDisplay");# this may not be what i'm looking to do.
    } else {
	# if we dont have a parent node, then just get the first one, hope its the right thing.
	#push(@vtkMRMLModelDisplayNodes,$mrml_data->{"MRML"}->{"ModelDisplay"}->[0]);
	@vtkMRMLModelDisplayNodes=mrml_find_by_id($mrml_data,$mrml_nodes[0]->{"displayNodeRef"}."\$"); # the display node ref); # could i just scalar that for how i'm doing things?
	if ( scalar(@vtkMRMLModelDisplayNodes) == 0  ){
	    die "Parent ref problem";
	} else {
	    #dump (@vtkMRMLModelDisplayNodes);
	    #exit;
	}
    }
    my $model_display_template = \%{clone $vtkMRMLModelDisplayNodes[0]};
    my $parent_hierarchy_node_id=$rootHierarchyNodeID;
    my $hierarchy_template = \%{clone $parent_ref};
    #dump($hierarchy_template);
    #sleep_with_countdown(3);
    my $sort_val=$#{$mrml_data->{"MRML"}->{"ModelHierarchy"}}; # current count of modelhierarchy nodes
    $hierarchy_template->{"sortingValue"}=$sort_val;
    my $level_show_bool=0; # bool to show what levels we've got when this loop ends. This is used to show error messages. 
    for(my $pn=0;$pn<=$#parts;$pn++){# proces the different levels of ontology, get the different ontology names, create a path to save the structure into.
	#
	my $branch_name=$parts[$pn];#meta structure name
		#use String::Util qw(trim); $branch_name=trim($branch_name)
	use Text::Trim qw(trim);# this doesnt work to limit the use of the Text::Trim module. Might as well be at the top of the script. 
	trim($branch_name);		
	my $tnum="";
	($tnum,$branch_name)= $branch_name =~/^([0-9]*_)?(.*)$/;
	$tnum="" unless defined $tnum;
	#universally trash tnum.
	$tnum="";

	#print("bn $branch_name\n");
	if ( ( 0 )
	     # THIS IS NOT DEACTIVATING THIS CODE, THIS IS FOR READABILITY LINEING THE CONDITIONS UP ON SUBSEQUENT LINES.
	     || ( not defined $branch_name ) 
	     || ( $branch_name eq '' ) 
	     || ( $branch_name =~ /^\s*$/ )
	     || ( $branch_name eq '0' ) 
	    ) {
	    #|| ( $branch_name == 0 ) ) {
	    
	    #warn("bad tree name($branch_name), skipping to additional levels");
	    #sleep_with_countdown(20);
	    $level_show_bool=1;
	    next; 
	    warn("bad tree name($branch_name), bailing on additional levels");
	    #sleep_with_countdown(20);
	    last; # drop out of the hierarchy builder
	}
	if ( 0 ) {
	if ( ( $branch_name =~ /_to_/x )
	     || ($branch_name =~/_and_/x) ){
	    warn('DIRTY MULTI NAME, LAMELY TAKING JUST THE FIRST.');
	    ### 
	    # @parts = $line =~ /([^\t]+)/gx;
	    ###
	    #my @b_parts= $branch_name =~ /(.*?)((:?_to_|_and_)(.*))*/gx; # this was a failure : (
	    my @b_parts=split("_to_",$branch_name);
	    my @b_parts2=split("_and_",$branch_name);
	    if ($#b_parts<$#b_parts2) {
		@b_parts=@b_parts2;
		# We're a range, now we should set up the whole range;
	    }
	    print("branch: $branch_name ");
	    dump(@b_parts);
	    $branch_name=$b_parts[0];
	} }
	if  ( 0 
	    && $branch_name =~ /^[rmp][0-9]{1,2}(?:[^\w]+[\w]*)?$/x) {
	    warn("\tAlex said to skip these structures($branch_name)");
	    next;
	}
	
	#$branch_name=~ s/[,\/#]/_/xg;#clean structure name of dirty elements replaceing them for underscores.
	$branch_name=~ s/[,\/# ]/_/xg;#clean structure name of dirty elements replaceing them for underscores.
	$s_path="$s_path/$tnum$branch_name"; #add cleanname to subpath.
	if ( ! defined (@{$l_1{$tnum.$branch_name}}) ) {
	    @{$l_1{$tnum.$branch_name}}=();
	    #print("\n---ON-level:$pn-UNDEF:$tnum$branch_name---\n");
	}
	if ( ! -d $s_path ){
	    print("mkdir $s_path\n") if ($debug_val>=45);
	    if ( $do_unsafe) {
		mkdir ($s_path);
	    }
	}
	push(@{$l_1{$tnum.$branch_name}},$value);
	if ( ! defined $ref->{$tnum.$branch_name}) {# clever way to build hierarchy hash on fly. The hierarchy hash is just a holder for the structure. It is only used here to keep track of whether we've sceen this node before or not.
	    my $spc=sprintf("  "x$pn);
	    print("$spc $branch_name not there, adding ... \n") if ($debug_val>=25);
	    $ref->{$tnum.$branch_name}={};
	    # update template with values for this structure.
	    $model_display_template->{"name"}=$branch_name."Display";
	    $model_display_template->{"id"}=$tnum.$branch_name."Display";
	    #$model_display_template->{"id"}="vtkMRMLModelDisplayNode".($hierarchy_template->{"sortingValue"}+1);
	    $model_display_template->{"color"}=sprintf("%0.0f",rand(1))
		." ".sprintf("%0.1f",rand(1))
		." ".sprintf("%0.1f",rand(1));
	    $model_display_template->{"visibility"}="false";
	    $hierarchy_template->{"name"}=$branch_name;
	    $hierarchy_template->{"id"}=$tnum.$branch_name;
	    $hierarchy_template->{"parentNodeRef"}=$parent_hierarchy_node_id;
	    $hierarchy_template->{"displayNodeID"}=$model_display_template->{"id"};
	    $hierarchy_template->{"sortingValue"}=$hierarchy_template->{"sortingValue"}+1;
	    $hierarchy_template->{"expanded"}="true";
	    # now add the template to MRML->ModelHierarchy and MRML->SceneView->ModelHierarchy
	    #push(@{$mrml_data->{"MRML"}->{"ModelHierarchy"}},%{clone $hierarchy_template});
	    push(@{$mrml_data->{"MRML"}->{"ModelHierarchy"}},\%{clone $hierarchy_template});
	    push(@{$mrml_data->{"MRML"}->{"ModelDisplay"}},\%{clone $model_display_template}); 
	    push(@{$mrml_data->{"MRML"}->{"SceneView"}->{"ModelHierarchy"}},\%{clone $hierarchy_template});
	    push(@{$mrml_data->{"MRML"}->{"SceneView"}->{"ModelDisplay"}},\%{clone $model_display_template});
	    #@vtkMRMLHieraryNodes=mrml_attr_search($mrml_data,"associatedNodeRef",$rootHierarchyNodeID."\$","ModelHierarchy");
	    # if the ref dont exist, we add it... hmm how/when do we set the type to vtkMRMLModelHierarchyNode?
	    #printf("--template_val--");
	    #dump($hierarchy_template);
	    #dump($mrml_data->{"MRML"}->{"ModelHierarchy"});
	    #dump($mrml_data->{"MRML"}->{"SceneView"}->{"ModelHierarchy"});
	    #dump($mrml_data->{"MRML"}->{"ModelDisplay"});
	    #dump($mrml_data->{"MRML"}->{"SceneView"}->{"ModelDisplay"});
	}
	#ast;
	$ref=$ref->{$tnum.$branch_name}; # this is our destination point for our structure once we've ensured the whole hierarchy before it is built.
	$parent_hierarchy_node_id=$tnum.$branch_name;
	#print("."x$pn);
	#print("\n");
    }
    if ( $level_show_bool ) {
	# Some levels haed issues here they all are.
	warn("bad tree name in group ( ".join(@parts," ")." ), skipping to additional levels");
    }
    my $node=$mrml_model;
    #display_complex_data_structure($node);

    my $storage_node_id;
    my $storage_node;
#    my $parent_hierarchy_node_id="BOGUS";
    my $mrml_node_id=$mrml_model->{"id"};    
    if ( defined $mrml_node_id  ) {
	my @model_hierarchy_nodes=mrml_attr_search($mrml_data,"associatedNodeRef",$mrml_node_id."\$","ModelHierarchy");
	$storage_node_id=$mrml_model->{"storageNodeRef"};
	
	    #print("found ".($#model_hierarchy_nodes+1)." references to this node\n");
	    foreach my $m_h_node ( @model_hierarchy_nodes){
		#print("change node $m_h_node->{id} $m_h_node->{name} to $alt_name\n");
		$m_h_node->{"parentNodeRef"}=$parent_hierarchy_node_id;
		if ( 1 ) {# renameing code, disabled for right now.
		if($rename_type eq 'clean' ){
		    $m_h_node->{"name"}="$alt_name";
		} elsif($rename_type eq 'Structure' ){ #was modelfile
		    $m_h_node->{"name"}="$model_prefix${value}_$alt_name";
		    $mrml_model->{"name"}="$model_prefix${value}_$alt_name";
		} elsif( $rename_type eq 'Name')  { #name?
		    $m_h_node->{"name"}="$mrml_name";
		    $mrml_model->{"name"}="$mrml_name";
		} elsif( $rename_type eq 'Abbrev')  { 
		    $m_h_node->{"name"}="$Abbrev";
		    $mrml_model->{"name"}="$Abbrev";
		} else { 
		    $m_h_node->{"name"}="$model_prefix${value}_$alt_name";
		    $mrml_model->{"name"}="$model_prefix${value}_$alt_name";
		}
		
	    }
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

}
print("processed $processed_nodes nodes\n");
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
	my $h_entry=$c_table->{"t_line"}->{$test_line};
	my $line;

	if ( 1 ) {
	    foreach (@fields) {
		if (! exists $h_entry->{$_} ){
		    printf($h_entry->{"Name"}." missing $_\n");
		    $h_entry->{$_}=0;
		}
	    }
	    $line=join(" ",@{$h_entry}{@fields})."\n";
	} else {
	$line=sprintf("%i %s %i %i %i %i\n",$h_entry->{"Value"},
			 $h_entry->{$rename_type},
			 $h_entry->{"c_R"},
			 $h_entry->{"c_G"},
			 $h_entry->{"c_B"},
			 $h_entry->{"c_A"});
	}
	push(@color_table_out,$line);
    }

    $test_line++;
}
write_array_to_file($p_color_table_out,\@color_table_out);
my @ontology_out=();
#my @o_columns=keys %{$o_table->{'Header'}};#keys %$o_table;
#@fields=qw(Structure Abbrev Level_1 Level_2 Level_3 Level_4 Value c_R c_G c_B c_A);# this was fine for the colortable as it had no header, but we can do better here.
@fields=();
#dump(%{$o_table->{"Header"}});#exit;
# this is the hash converstion code lets use it to build an inverse hash.. 
my %h_o_hash;@h_o_hash{values(%{$o_table->{"Header"}})}=keys(%{$o_table->{"Header"}});#dump(%h_o_hash);#exit;
foreach my $idx (sort {$a<=>$b} (keys(%h_o_hash)) ) {# HAD TO FORCE NUMERCAL OR THIS WOULDNT WORK AS EXPECTED.
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
	my $h_entry=$o_table->{"t_line"}->{$test_line};
	my $c_entry=$c_table->{"Structure"}->{$h_entry->{"Structure"}};
	if ( ! defined $c_entry ){
	    my @c_vals=qw(c_R c_G c_B c_A);
	    @{$h_entry}{@c_vals}=(255) x scalar(@c_vals);
	    $h_entry->{"Value"}=0;
	    print("Extranous ontology entry($h_entry->{Structure})!\n");
	    #sleep_with_countdown(2);
	} else {
	    my @c_vals=qw(c_R c_G c_B c_A Value);
	    # set the o_entry color info to the c_table info.
	    #dump(@{$c_entry}{@c_vals});
	    @{$h_entry}{@c_vals}=@{$c_entry}{@c_vals};
	}

	
	my $line;
	if ( 1 ) {
	    my @values=@{$h_entry}{@fields};
	    # trim the organizational numbef off the names of levels
	    my $start_field=2;
	    for (my $vn=$start_field;$vn<$start_field+4;$vn++){
		$values[$vn]=~s/^[0-9]+_//gx;
	    }
	    # make the output line
	    $line=join("\t",@values)."\n";
	} else {
	    $line=sprintf("%i %s %i %i %i %i\n",$h_entry->{"Value"},
			 $h_entry->{$rename_type},
			 $h_entry->{"c_R"},
			 $h_entry->{"c_G"},
			 $h_entry->{"c_B"},
			  $h_entry->{"c_A"});
	}
	push(@ontology_out,$line);
    }

    $test_line++;
}
write_array_to_file($p_ontology_out,\@ontology_out);

exit;exit;exit;
exit;exit;exit;
exit;exit;exit;
exit;exit;exit;
exit;exit;exit;
exit;exit;exit;
exit;exit;exit;
exit;exit;exit;
exit;exit;exit;
exit;exit;exit;
exit;exit;exit;
exit;exit;exit;
exit;exit;exit;
exit;exit;exit;
exit;exit;exit;
exit;exit;exit;
exit;exit;exit;
exit;exit;exit;
exit;exit;exit;
exit;exit;exit;
my @ontology_csv; 
load_file_to_array($p_ontology_in,\@ontology_csv);
print("color_table ".($#ontology_csv+1)." lines loaded\n");
print("ontology ".($#ontology_csv+1)." lines loaded\n");
@mrml_nodes_loaded=mrml_find_by_id($mrml_data,".*"); # could i just scalar that for how i'm doing things?
print("mrml ".($#mrml_nodes_loaded+1)." nodes loaded\n");


my @parts;
my @ontology_sheet_columns;
my %ontology_header_index=();
my @ontology_label_fields=();
my @ontology_color_fields=();
#my %l_1;
#my %onto_hash=();
# my %l_2;
# my %l_3;
# my %l_4;
# my %l_5;

#pull the column headers off the csv file, clean up their names.
my $line=shift(@ontology_csv);
$line =~ s/[ ]/_/gx;#space for underscore.
chomp($line);
@parts = $line =~ /([^\t]+)/gx;
if ( $#parts < 3) {
    warn("Used commas instead of tabs, You better have clean names.");
    @parts = $line =~ /([^,]+)/gx;
}
if($#ontology_sheet_columns==-1 && $#parts >= 3){
    print("ontology_sheet_columns assign:".join(" ",@parts)."\n");
    @ontology_sheet_columns=@parts;
    my $colN=0;

    foreach (@parts){
	$ontology_header_index{$_}=$colN;
	if ( $_ =~ /Level_[0-9]/x ) {
	    push(@ontology_label_fields,$_);
	} elsif ($_ =~ /^c_[RGBA]$/x ) {
	    push(@ontology_color_fields,$_);
	}
	$colN++;
    }
}
#($who, $home)  = @ENV{"USER", "HOME"};      # hash slice
@ontology_label_fields=sort(@ontology_label_fields);

#@ontology_color_fields=sort(@ontology_color_fields);#this will unfortunately sort color columns, what I really need is them to be consistent.So, this is ok beacuase we're not going to really use them, and if we do we know c_A is alpha, c_B is blue, c_G is green, and c_R is red. AH but it DOES matter, because we want to compare to the values in the slicer color table so the order MUST match.
# Lets switch then to checking if the appropriate number of entries exist, and THEN setting a constant order.
if ($#ontology_color_fields==3){ #cuz there are f :p
    printf("set onto. color fields\n");
    @ontology_color_fields=qw(c_R c_G c_B c_A); 
} else {
    printf("No onto. color fields\n");
}
    
#dump(@ontology_label_fields);
#exit;
my @d_Abbrev;   #input dirty Abbreviaion files found
my @d_a_found; # output dirty Abbreviaions files found
my @d_name;    #intput dirty name files found
my @d_n_found; # output dirty name files found
my @c_name;    #input clean name files found
my @c_n_found; # output clean name files found
#my $do_unsafe=0;
my ($process_Abbrev_names,$process_full_names)=(0,0);
#my @model_hierarchy_nodes=mrml_find_by_name($mrml_data,".*","ModelHierarchy");# should return only ModelHierarchyNodes
# not that i'm using this variabl, so i'm commenting it out.


# if ( ! defined $ref->{$tnum.$branch_name}) {# clever way to build hierarchy hash on fly. The hierarchy hash is just a holder for the structure. It is only used here to keep track of whether we've sceen this node before or not.
#     my $spc=sprintf("  "x$pn);
#     print("$spc $branch_name not there, adding ... \n") if ($debug_val>=25);
#     $ref->{$tnum.$branch_name}={};
#     # update template with values for this structure.
#     $model_display_template->{"name"}=$branch_name."Display";
#     $model_display_template->{"id"}=$tnum.$branch_name."Display";
#     #####$model_display_template->{"id"}="vtkMRMLModelDisplayNode".($hierarchy_template->{"sortingValue"}+1);
#     $model_display_template->{"color"}=sprintf("%0.0f",rand(1))
# 	." ".sprintf("%0.1f",rand(1))
# 	." ".sprintf("%0.1f",rand(1));
#     $model_display_template->{"visibility"}="false";
#     $hierarchy_template->{"name"}=$branch_name;
#     $hierarchy_template->{"id"}=$tnum.$branch_name;
#     $hierarchy_template->{"parentNodeRef"}=$parent_hierarchy_node_id;
#     $hierarchy_template->{"displayNodeID"}=$model_display_template->{"id"};
#     $hierarchy_template->{"sortingValue"}=$hierarchy_template->{"sortingValue"}+1;
#     $hierarchy_template->{"expanded"}="true";
#     # now add the template to MRML->ModelHierarchy and MRML->SceneView->ModelHierarchy
#     #####push(@{$mrml_data->{"MRML"}->{"ModelHierarchy"}},%{clone $hierarchy_template});
#     push(@{$mrml_data->{"MRML"}->{"ModelHierarchy"}},\%{clone $hierarchy_template});
#     push(@{$mrml_data->{"MRML"}->{"ModelDisplay"}},\%{clone $model_display_template}); 
#     push(@{$mrml_data->{"MRML"}->{"SceneView"}->{"ModelHierarchy"}},\%{clone $hierarchy_template});
#     push(@{$mrml_data->{"MRML"}->{"SceneView"}->{"ModelDisplay"}},\%{clone $model_display_template});
#     #####@vtkMRMLHieraryNodes=mrml_attr_search($mrml_data,"associatedNodeRef",$rootHierarchyNodeID."\$","ModelHierarchy");
# }









####
# New method, we have our text spreadsheets loaded.
####
# we should look at each models from the xml, or from the color table.
#foreach model in mrml_data
#@mrml_nodes=mrml_find_by_name($mrml_data,".*",$alt_name,"Model");
#@mrml_nodes=mrml_find_by_name($mrml_data->{"MRML"}->{"SceneView"},".*",$alt_name,"Model");
#  while level_next exists, check for level, add it
#  add wiring....?



exit;
my @color_table_lines;
foreach $line (@ontology_csv) {
    chomp($line);
    #@parts = $line =~ /([^\t]+)/gx;# WHY DIDNT I USE SPLIT!!!!!
    @parts = split("\t",$line);
    if ( $#parts < 3) {
	warn("Used commas instead of tabs, You better have clean names.") unless ($debug_val<45);
	#@parts = $line =~ /([^,]+)/gx;# WHY DIDNT I USE SPLIT!!!!!
	@parts = split(',',$line);
    }
    chomp(@parts);
    #
    #print(join(':',@parts)."\n");
    if ( 0 ) { 
	#print("$#parts");
	#print("$#parts:$line\n");
    } elsif ( $#parts >= 3) {
	#print("......");
	### INACTIVE
	if ( 0 ) { # first pass for parse.
	    my $struct_num=$parts[$#parts];
	    #print("add struct $parts[$#parts]\t");
	    for(my $pn=$#parts-1;$pn>1;$pn--){
		# 
		my $a_name=$parts[$pn];#$ontology_sheet_columns[$pn]
		$a_name=~ s/[,\/#]/_/xg;
		if ( ! defined (@{$l_1{$a_name}}) ) { 
		    @{$l_1{$a_name}}=(); 
		    #print("\n---ON-level:$pn-UNDEF:$a_name.---\n");
		}
		push(@{$l_1{$a_name}},$struct_num);
	    }
	    @parts=@parts[2-($#parts-1)];
	    print(join(',',@parts));#:
	    print("<- $struct_num \n");
	}
	### ENDINACTIVE

	#my $name=shift(@parts);
	# changed from the hard set order to one determined by tab sheet header
	# uses a hash with col_header=position and pulls that from parts.
	# then cuts down parts to just the level fields.
	# i need to check for color information and pull that separately, as an alternative to value. 
	my $name=$parts[$ontology_header_index{"Structure"}];
	#my $Abbrev=shift(@parts);
	my $Abbrev=$parts[$ontology_header_index{"Abbrev"}];
	#my $value=pop(@parts);
	my $value=$parts[$ontology_header_index{"Value"}];
	my $color='NULL';
	if ( not defined( $value ) ) {
	    warn("NO Value $name");
	    $value=100000;
	}
	if ( $#ontology_color_fields==3 ) { # the case this is fixes should NEVER happen, its just bugging out on test data.
	    $color=join(@parts[@ontology_header_index{@ontology_color_fields}]);
	}
	@parts=@parts[@ontology_header_index{@ontology_label_fields}];
	
	#dump(@parts);
	my ($a_fn,$c_fn,$f_fn)=('','','');
	my (@a_path,@s_path,@f_path)=((),(),());
# 		if ( ! -d './MoldelTree/'.join('/',@parts) ){
# 		    print("mkdir './ModelTree/'.join('/',@parts)\n");
# 		}
	if ( 1) { 
	    #print("#$Abbrev:$name\n");
	    my $s_path='Static_Render/LabelModels';
	    my $ref=\%onto_hash;
	    my $parent_ref=$rootHierarchyNode;
	    my @vtkMRMLModelDisplayNodes=mrml_attr_search($mrml_data,"id",$parent_ref->{"displayNodeID"}."\$","ModelDisplay");# this may not be what i'm looking to do.
	    my $model_display_template = \%{clone $vtkMRMLModelDisplayNodes[0]};
	    my $parent_hierarchy_node_id=$rootHierarchyNodeID;
	    my $hierarchy_template = \%{clone $parent_ref};
	    #dump($hierarchy_template);
	    #sleep_with_countdown(3);
	    my $sort_val=$#{$mrml_data->{"MRML"}->{"ModelHierarchy"}}; # current count of modelhierarchy nodes
	    #my $display_node_num=$#{$mrml_data->{"MRML"}->{"ModelDisplay"}};# was going to just set names like slicer does, but that would assume that slicer's vtkrMRMLModelDisplayNodes start numbering at 1/0. That is not a safe assumption. 
	    $hierarchy_template->{"sortingValue"}=$sort_val;
	    #for(my $pn=$#parts;$pn>=0;$pn--){
	    #print("PARTS: '".join("' '",@parts)."'.\n");
	    for(my $pn=0;$pn<=$#parts;$pn++){# proces the different levels of ontology, get the different ontology names, create a path to save the structure into.
		#
		my $branch_name=$parts[$pn];#meta structure name
		#use String::Util qw(trim); $branch_name=trim($branch_name)
		use Text::Trim qw(trim);
		trim($branch_name);
		#print("bn $branch_name\n");
		if ( ( 0 )
		     || ( not defined $branch_name ) 
		     || ( $branch_name eq '' ) 
		     || ( $branch_name =~ /^\s*$/ )
		     || ( $branch_name eq '0' ) 
		    ) {
			 #|| ( $branch_name == 0 ) ) {
		    warn("bad tree name, bailing on additional levels");
		    #sleep_with_countdown(20);
		    last; # drop out of the hierarchy builder
		}
		if ( $branch_name =~ /^[rmp]/x) {
		    warn("\tAlex said to skip these structures");
		    next;
		}
		if ( ( $branch_name =~ /_to_/x )
		     || ($branch_name =~/_and_/x) ){
		    warn('DIRTY MULTI NAME, LAMELY TAKING JUST THE FIRST.');
		    ### 
		    # @parts = $line =~ /([^\t]+)/gx;
		    ###
		    #my @b_parts= $branch_name =~ /(.*?)((:?_to_|_and_)(.*))*/gx; # this was a failure : (
		    my @b_parts=split("_to_",$branch_name);
		    my @b_parts2=split("_and_",$branch_name);
		    if ($#b_parts<$#b_parts2) {
			@b_parts=@b_parts2;
			# We're a range, now we should set up the whole range;
		    }
		    print("branch: $branch_name ");
		    dump(@b_parts);
		    $branch_name=$b_parts[0];
		}
		
		my $tnum="";
		($tnum,$branch_name)= $branch_name =~/^([0-9]*_)?(.*)$/;
		$tnum="" unless defined $tnum;

		#$branch_name=~ s/[,\/#]/_/xg;#clean structure name of dirty elements replaceing them for underscores.
		$branch_name=~ s/[,\/# ]/_/xg;#clean structure name of dirty elements replaceing them for underscores.
		$s_path="$s_path/$tnum$branch_name"; #add cleanname to subpath.
		if ( ! defined (@{$l_1{$tnum.$branch_name}}) ) {
		    @{$l_1{$tnum.$branch_name}}=();
		    #print("\n---ON-level:$pn-UNDEF:$tnum$branch_name---\n");
		}
		if ( ! -d $s_path ){
		    print("mkdir $s_path\n") if ($debug_val>=45);
		    if ( $do_unsafe) {
		    mkdir ($s_path);# oh yea, we can make_path instead...
		    }
		}

		# look up in colortable structure.
		#name= structure in color_table
		#abbrev should be equivalent.
		my $s_hash={};
		if ( $c_table->{"Abbrev"}->{$Abbrev} ){
		    $s_hash=$c_table->{"Abbrev"}->{$Abbrev};
		} elsif ( $c_table->{"Structure"}->{$name} ) {
		    $s_hash=$c_table->{"Structure"}->{$name};
		}
		if ( scalar($s_hash) > 0 ) {
		    if ( exists($s_hash->{"Value"}) ){ 
			$value=$s_hash->{"Value"}; 
		    } else {
			warn("color_table hash $Abbrev missing value.");
		    }
		}
		push(@{$l_1{$tnum.$branch_name}},$value);
		if ( ! defined $ref->{$tnum.$branch_name}) {# clever way to build hierarchy hash on fly. The hierarchy hash is just a holder for the structure. It is only used here to keep track of whether we've sceen this node before or not.
		    my $spc=sprintf("  "x$pn);
		    print("$spc $branch_name not there, adding ... \n") if ($debug_val>=25);
		    $ref->{$tnum.$branch_name}={};
		    # update template with values for this structure.
		    $model_display_template->{"name"}=$branch_name."Display";
		    $model_display_template->{"id"}=$tnum.$branch_name."Display";
		    #$model_display_template->{"id"}="vtkMRMLModelDisplayNode".($hierarchy_template->{"sortingValue"}+1);
		    $model_display_template->{"color"}=sprintf("%0.0f",rand(1))
			." ".sprintf("%0.1f",rand(1))
			." ".sprintf("%0.1f",rand(1));
		    $model_display_template->{"visibility"}="false";
		    $hierarchy_template->{"name"}=$branch_name;
		    $hierarchy_template->{"id"}=$tnum.$branch_name;
		    $hierarchy_template->{"parentNodeRef"}=$parent_hierarchy_node_id;
		    $hierarchy_template->{"displayNodeID"}=$model_display_template->{"id"};
		    $hierarchy_template->{"sortingValue"}=$hierarchy_template->{"sortingValue"}+1;
		    $hierarchy_template->{"expanded"}="true";
		    # now add the template to MRML->ModelHierarchy and MRML->SceneView->ModelHierarchy
		    #push(@{$mrml_data->{"MRML"}->{"ModelHierarchy"}},%{clone $hierarchy_template});
		    push(@{$mrml_data->{"MRML"}->{"ModelHierarchy"}},\%{clone $hierarchy_template});
		    push(@{$mrml_data->{"MRML"}->{"ModelDisplay"}},\%{clone $model_display_template}); 
		    push(@{$mrml_data->{"MRML"}->{"SceneView"}->{"ModelHierarchy"}},\%{clone $hierarchy_template});
		    push(@{$mrml_data->{"MRML"}->{"SceneView"}->{"ModelDisplay"}},\%{clone $model_display_template});
		    #@vtkMRMLHieraryNodes=mrml_attr_search($mrml_data,"associatedNodeRef",$rootHierarchyNodeID."\$","ModelHierarchy");
		    # if the ref dont exist, we add it... hmm how/when do we set the type to vtkMRMLModelHierarchyNode?
		    #printf("--template_val--");
		    #dump($hierarchy_template);
		    #dump($mrml_data->{"MRML"}->{"ModelHierarchy"});
		    #dump($mrml_data->{"MRML"}->{"SceneView"}->{"ModelHierarchy"});
		    #dump($mrml_data->{"MRML"}->{"ModelDisplay"});
		    #dump($mrml_data->{"MRML"}->{"SceneView"}->{"ModelDisplay"});
		}
		#ast;
		$ref=$ref->{$tnum.$branch_name}; # this is our destination point for our structure once we've ensured the whole hierarchy before it is built.
		$parent_hierarchy_node_id=$tnum.$branch_name;
		#print("."x$pn);
		#print("\n");
	    }

	    my @mrml_nodes;
	    my $alt_name=$name;
	    my $storage_node_id="";
	    my $storage_node={};
	    my $node={};
	    my $file_name="$model_prefix${value}_${alt_name}";
	    {# safe but ugly name_handle
		$alt_name=~ s/,[ ]/CMA/gx;
		$alt_name=~ s/[ ]/SPC/gx;
		$alt_name=~ s/,/CMA/gx;
		$alt_name=~ s/\//FSLASH/gx;
		$alt_name=~ s/\+/PLS/gx;
		#$alt_name=~ s/\(/\\(/gx;
		#$alt_name=~ s/\)/\\)/gx;
		$c_fn=$alt_name;

		###
		# check ontology value in color_table, see that their name matches.
		# THIS IS BOGUS NOW THAT OUR NAMES AND THE HIERARCHY HAVE FALLEN OUT OF DATE.
		# value matching our ontology.
		###
		if(0){

		for(my $ct_i=0;$ct_i<=$#color_table_lines;$ct_i++) { 
		    my $cte=$color_table_lines[$ct_i];
		    #print($cte);
		    if ( $cte !~ /^#.*/ ) {
			my @ct_entry=split(' ',$cte);
			#print("ct:".join(" ",@ct_entry)."\n");
			if ( $value == $ct_entry[0] &&  $#ct_entry>=4) { 
			    if($alt_name ne $ct_entry[1]) {
				print("COLOR_TABLE NAME FAILURE($value) generated : $alt_name, color_table $ct_entry[1]\n");
			    }
			    #$ct_entry[1]="$model_prefix${value}_$alt_name";
			    $ct_entry[1]="$alt_name";
			    #$color_table_lines[$ct_i]=join(@ct_entry,' ');
			    $color_table_lines[$ct_i]=join(' ',@ct_entry)."\n";
			}
		    }
		}}
	    }
	    
	    ###
	    # fix the name in our xml_out.
	    ###
	    # find any mrml nodes with name = alt name 
	    # using the id from the model node,
	    #   get the modelhierarchy that controls our location by looking at associateNodeRef = our id.
	    # rename that modelhierarchy to alt_name,this didnt work, try again using v1_value_alt_name
	    
	    @mrml_nodes=mrml_find_by_name($mrml_data,$alt_name,"Model");
	    if ( scalar @mrml_nodes !=1 ){
		printf("MISSING $alt_name:".scalar @mrml_nodes."\n");
		@mrml_nodes=mrml_find_by_name($mrml_data,($model_prefix.$value."_"),"Model"); 
		printf("\t ${model_prefix}${value}_:".scalar @mrml_nodes."\n");
		if ( scalar @mrml_nodes !=1 ){
		    @mrml_nodes=mrml_find_by_name($mrml_data,($model_prefix.'[0-9]+_'.$Abbrev."__"),"Model");
		    printf("\t $Abbrev:".scalar @mrml_nodes."\n");
		# abbreviation alone isnt precise enough, adding model_prefix and proximate value, 
		# adding a double underscore to eliminate false positives.
		}
		
		if ( scalar @mrml_nodes !=1 ){
		    print("\t wrong count after two tries!\n");
		    next;
		}
	    }
	    for(my $ri=0;$ri<$#mrml_nodes;$ri++){
		if ( mrml_node_diff($mrml_nodes[$ri],$mrml_nodes[$ri+1]) ) { 
		    warn("more nodes found than expected!($#mrml_nodes)".join(@mrml_nodes,' ')."\n");
		    sleep_with_countdown(3);
		}   
	    }
	    $node=$mrml_nodes[0];
	    #display_complex_data_structure($node);
	    my $node_id=$node->{"id"};
	    if ( defined $node_id  ) {
		my @mrmls_found=mrml_attr_search($mrml_data,"associatedNodeRef",$node_id."\$","ModelHierarchy");
		$storage_node_id=$node->{"storageNodeRef"};
		#print("found ".($#mrmls_found+1)." references to this node\n");
		foreach my $mrml_node ( @mrmls_found){
		    #print("change node $mrml_node->{id} $mrml_node->{name} to $alt_name\n");
		    if($rename_type eq 'clean' ){
			$mrml_node->{"name"}="$alt_name";
		    } elsif($rename_type eq 'modelfile' ){
			$mrml_node->{"name"}="$model_prefix${value}_$alt_name";
			$node->{"name"}="$model_prefix${value}_$alt_name";
		    } elsif( $rename_type eq 'ontology')  {
			$mrml_node->{"name"}="$name";
			$node->{"name"}="$name";
		    } elsif( $rename_type eq 'Abbrev')  { 
			$mrml_node->{"name"}="$Abbrev";
			$node->{"name"}="$Abbrev";
		    } else { 
			$mrml_node->{"name"}="$model_prefix${value}_$alt_name";
			$node->{"name"}="$model_prefix${value}_$alt_name";
		    }
		    $mrml_node->{"parentNodeRef"}=$parent_hierarchy_node_id;
		}
	    } else {
		if (!scalar $node ){
		    warn("OHh NOOOO node id not set ! Sleeping a bit while you look at this!");
		    dump($node);
		    sleep_with_countdown(15);
		} else {
		    warn("$alt_name not found!");
		}
		next;
	    }
	    my @s_nodes=mrml_attr_search($mrml_data,"id",$storage_node_id."\$","ModelStorage");
	    $storage_node=$s_nodes[0];#close enough ; )
	    my $file_src="Static_Render/ModelTree/$file_name.vtk";
	    if ( scalar %{$storage_node} ) {
		$file_src=$storage_node->{"fileName"};
            } else {
		warn("Using assumed source filename");
	    }
	    my $file_dest='Static_Render/ModelTree/'.join('/',@parts)."/$file_name.vtk";
	    $file_dest="$s_path/$file_name.vtk";
	    $file_dest=~ s/[ ]/_/gx;
	    my @c_path=($file_src,$file_dest);
	    if ( ! -f $file_dest) { 
		if ( -e $file_src ) { 
		    push(@c_name,$file_name.".vtk");
		    print("mv $file_src $file_dest\n") if ($debug_val>=45);
		    if ( $do_unsafe ) {
			rename($file_src, $file_dest);
		    }
		} else {
		    print ("\t #missing $file_src\n");
		}
	    } else {
		#rename($file_dest,$file_src);
		push(@c_n_found,$file_dest);
		
	    }
	    if ( scalar %{$storage_node} && $do_unsafe) {
		print("setting new file path in mrml\n");
		$storage_node->{"fileName"}=$file_dest;
	    }
	    $ref->{$alt_name}=$value;
	    
	    if ( $process_Abbrev_names ) { #Abbrev name_handle
		print("Abbrev name \n");
		$alt_name=$Abbrev;
		$alt_name=~ s/[ ]/_/gx;
		$alt_name=~ s/,/_/gx;
		$alt_name=~ s/\//_/gx;
		$alt_name=~ s/\+/_/gx;
		#$alt_name=~ s/\(/\\(/gx;
		#$alt_name=~ s/\)/\\)/gx;
		$a_fn=$alt_name;
		$file_name="$model_prefix${value}_${alt_name}";
		my $file_dest="Static_Render/LabelModels_Abbrev/$file_name.vtk";
		@a_path=($file_src,$file_dest);
		if ( ! -f $file_dest) {
		    if ( -e $file_src ) { 
			push(@d_Abbrev,$file_name.".vtk");
			print("mv $file_src $file_dest\n");
			if ( $do_unsafe ) {
			    rename($file_src, $file_dest);
			    if ( scalar %{$storage_node} ) {
				$storage_node->{"fileName"}=$file_dest;
			    }
			}
		    } else {
			print ("\t #missing $file_src\n");
		    }
		    
		} else {
		    push(@d_a_found,$file_dest);
		}
	    }
	    if ( $process_full_names ) {# full name_handle
		print("Full name \n");
		$alt_name=$name;
		#$alt_name=~ s/[ ]/_/gx;
		$alt_name=~ s/\/[^\s]+//gx;
		$alt_name=~ s/,[ ]//gx;
		$alt_name=~ s/,//gx;
		
		$alt_name=~ s/\+//gx;
		#$alt_name=~ s/\(/\\(/gx;
		#$alt_name=~ s/\)/\\)/gx;
		#$f_fn=$alt_name;
		$file_name="${alt_name}";
		my $file_dest="Static_Render/LabelModels_full_names/$file_name.vtk";
		my @f_path=($file_src,$file_dest);
		if ( ! -f $file_dest) {
		    if ( -e $file_src ) { 
			push(@d_name,$file_name.".vtk");
			print("mv $file_src $file_dest\n");
			if ( $do_unsafe ) {
			    rename($file_src, $file_dest);
			    if ( scalar %{$storage_node} ) {
				$storage_node->{"fileName"}=$file_dest;
			    }
			}
		    } else {
			print ("\t #missing $file_src\n");
		    }
		} else {
		    push(@d_n_found,$file_dest);
		}
	    }
	    # find the ref in the ontolgy mrml
	}
	
    }
    #for cn=1:$#ontology_sheet_columns,ontology_sheet_columns,push onto hash{colheader(cn)},parts(cn)
    #print  SESAME_OUT $line;  # write out every line modified or not
#    dump @parts;
    #    last;
    
}

#dump($mrml_data->{"MRML"}->{"ModelHierarchy"});
#dump($mrml_data->{"MRML"}->{"ModelDisplay"});
print("PROCESS SUMMARY\n".
      "\ttotal_possiblities:$#ontology_csv, \n".
      "\tcandidates available and unprocessed, \n".
      "\t#unprocessed clean_names:$#c_name,\n".
      "\t#unprocessed dirty_names:$#d_name,\n".
      "\t#unprocessed dirty_Abbrevs:$#d_Abbrev\n".
      "candidates found at dest\n".
      "clean_names:$#c_n_found,\n".
      "dirty_names:$#d_n_found,\n".
      "dirty_Abbrevs:$#d_a_found\n");
print(join(':',@ontology_sheet_columns)."\n");
print('larger_level_structures >');
my @list=keys(%l_1);
for my $kn (@list)  {
    my @s_list=@{$l_1{$kn}};
    #print("\t$kn:$#{$l_1{$kn}}\n");
    #print("($model_prefix".join('_|$model_prefix',@{$l_1{$kn}}),")\n");#elements regex
}
#display_complex_data_structure(\%onto_hash,'  ',0,'noleaves'); # noleaves doenst exactly work because some trees have twigs foreach leaf
#display_complex_data_structure(\%onto_hash);

#xml_write($mrml_data,$p_mrml_out_template)
printf("ontology built\n");
dump(%onto_hash);
#dump(%l_1);
sleep_with_countdown(3);
   

mrml_to_file($mrml_data,'  ',0,'pretty','',$p_mrml_out);
if( $rename_type eq 'modelfile' || $rename_type eq 'ontology' || $rename_type eq 'Abbrev') {
    mrml_clear_nodes($mrml_data,("ModelHierarchy","ModelDisplay","Version", "UserTags"));
    mrml_to_file($mrml_data,'  ',0,'pretty','',$p_mrml_out_template);
    write_array_to_file($p_color_table_out,\@color_table_lines);
}#$rename_type eq 'clean' ||
#close SESAME_OUT; 

# when you are sure this is working add... 
# rename $outpath, $p_ontology_in;  # destroys p_ontology_in, change name of file f

#    $cmd = "copy $ARGV[0] $ARGV[0].bak";
#    system($cmd);
#    $outpath=$ARGV[0].bak;



sub cleanup_ontology_levels {
    # This is a cleanup function, to make sure bad ontology data doesnt pollute what we're doing later on.
    # it needst o take the onotology hash table, and turn it into a hierarchical structure.
    #
    # Plan is to do this in two passes. First pass operates on each line of ontology; 
    # it ensures unique structure names/abbreviations/value, and adds levels to a listing of seen super structures.
    # The second pass goes through the seen super structures and tries to find their parent structure.
    my ($o_table)=@_;
    my $onto_hash={}; #$onto_hash->{"test"}="foo";
    # onto_hash will have 4 parts.
    # onto SuperStructures, branches with many leaves, by their line number
    # onto num_lookup, the superstructures with their ordering number if they've got one. Only the first number found will be used for any group.
    # onto line_to_struct, lookup of linenumber and to SuperStructure
    # onto branches, once we have the other two components we'll try to back calculate the ontology lookup.
    
    my @o_columns=keys %{$o_table->{'Header'}};#keys %$o_table;
    #dump(@o_columns); #dump($o_table->{$o_columns[0]}); # a worse version of the commented test.
    #dump($o_table->{"t_line"}); # test that we have contents by line in our table.
    my $seen={};
    $seen->{"Value"}={};
    $seen->{"Structure"}={};
    $seen->{"Abbrev"}={};
    $seen->{"Name"}={};
    my @onto_errors=();
    my @onto_error_msgs=();
    foreach (keys( %{$o_table->{"t_line"}}) ) {
    	#dump($_);
	#dump(ref $_);
	my $o_entry=$o_table->{"t_line"}->{$_};
	# TODO: get the keys, make sure they are all part of the ontology header.
	#%{$o_table->{'Header'}}; 
	#dump($o_entry);
	#dump(ref $o_entry);

	#
	# error check our o_entry ( duplicates ).
	#
	my @error_fields=();
	for my $check_field (keys(%$seen)) {
	    if ( ! exists($seen->{$check_field}->{$o_entry->{$check_field}})  ){
		push(@{$seen->{$check_field}->{$o_entry->{$check_field}}},$_);#$o_entry->{$check_field});
		#$seen->{$check_field}->{$o_entry->{$check_field}} = ($o_entry->{$check_field});
	    } else {
		push(@onto_errors,$seen->{$check_field}->{$o_entry->{$check_field}});
		push(@onto_error_msgs,"ERROR duplicate ontology $check_field line ".$o_entry->{"t_line"}.".");
		push(@{$seen->{$check_field}->{$o_entry->{$check_field}}},$o_entry->{"t_line"});#$o_entry->{$check_field});
		push(@error_fields,$check_field);
	    }
	}
	if(scalar(@error_fields)==1) {# there's only one error for this entry,
	    if ( $error_fields[0] eq "Abbrev" ) { # and its in the Abbreviation.
		# Then we can fix this, note these two steps MUST be peformed in this order.
		# First; 
		# Get first t_line.
		my $first_line=$seen->{"Abbrev"}->{$o_entry->{"Abbrev"}}[0];
		# MIGHT want to do the minimum t_line instead of just the first one found, what with hashes not having guarnteed order and all. 
		#dump($first_line);
		my $first_entry=$o_table->{"t_line"}->{$first_line};
		# Fix the lookup table.
		$o_table->{"Abbrev"}->{$first_entry->{"Abbrev"}}=$first_entry;
		# Second;
		# Fix our personal entry, set abbreviation to name. 
		$o_entry->{"Abbrev"}=$o_entry->{"Name"};
		push(@onto_error_msgs,"\t ".$o_entry->{"t_line"}." Fixed by dumping the abbreviation");
	    }
	}
	my @parts=sort(keys %$o_entry); # get all the info types for this structure sorted.
	#my @parts=@o_columns;
	@parts=grep {/Level_[0-9]+$/} @parts; # pair that down to only different ontology levels.
	if (scalar(@parts)>0 ) {
	    print("\t got ".scalar(@parts)."\n") if $debug_val>=45;
	    #dump(%$o_entry); # this works.
	    #dump(%{$o_entry{@parts}}); # his doesnt.
	    #dump(%{$o_entry}); this works
	    #dump(@{$o_entry}{@parts});# THIS WORKS!!!!
	    #dump($o_entry->{@parts});# this is undef
	    #dump(@$o_entry->{@parts});# not an array reference
	    #dump(@$o_entry{@parts});# THIS WORKS!
	    @parts=@{$o_entry}{@parts}; # Now get the values at each present level. 
	} else {
	    @parts=();
	}
	#
	# Get ontology levels and assign structure to the different levels in the ultra meta hash.
	#
	my @onto_levels=();my $level_show_bool=0;
	print($o_entry->{"Name"}."\t".$o_entry->{"t_line"}."\n");
	for(my $pn=0;$pn<=$#parts;$pn++){
	    # process the different levels of ontology, get the different ontology names.
	    # clean them up and put them into the onto_levels list.
	    my $branch_name=$parts[$pn]; # meta structure name
	    trim($branch_name);
	    my $tnum="";
	    ($tnum,$branch_name)= $branch_name =~/^([0-9]*_)?(.*)$/;
	    $tnum="" unless defined $tnum;
	    #universally trash tnum.
	    #$tnum="";
	    #$branch_name=~ s/[,\/#]/_/xg;#clean structure name of dirty elements replaceing them for underscores.
	    $branch_name=~ s/[,\/# ]/_and_/xg;#clean structure name of dirty elements replacing them with _and_.
	    $branch_name=~ s/[-\/# ]/_to_/xg;#clean structure name of dirty elements replacing them with _to_.
	    
	    #print("bn $branch_name\n");
	    if ( ( 0 )
		 # THIS IS NOT DEACTIVATING THIS CODE, THIS IS FOR READABILITY LINEING THE CONDITIONS UP ON SUBSEQUENT LINES.
		 || ( not defined $branch_name ) 
		 || ( $branch_name eq '' ) 
		 || ( $branch_name =~ /^\s*$/ )
		 || ( $branch_name eq '0' ) 
		) {
		$level_show_bool=1;
		warn("bad tree name, skipping to next level");
		next; 
	    }
	    if ( ( $branch_name =~ /_to_/x )
		 || ($branch_name =~/_and_/x) ){
		#warn('DIRTY MULTI NAME, LAMELY TAKING JUST THE FIRST.');
		### 
		# @parts = $line =~ /([^\t]+)/gx;
		###
		#my @b_parts= $branch_name =~ /(.*?)((:?_to_|_and_)(.*))*/gx; # this was a failure : (
		if ( ( $branch_name =~ /_to_/x )
		     && ($branch_name =~/_and_/x) ) {
		    die("WOW Really trying to get me arnt you!");
		}
		my @b_parts=split("_and_",$branch_name);
		# foreach b_part convert _ to space, and then trim to clean up erroneous underscores.
		my @tmp=();
		# THIS ALL FEELS SO CLUNKY, THERE MUST BE A MORE PERLY, CLEAVER WAY
		while ( my $b_and =shift(@b_parts)) {
		    $_=~ s/_/ /xg;#clean structure name of dirty elements replacing them for underscores.
		    #if ( $b_and =~ /_to_/x ) {
		    #    die("WOW Really trying to get me arnt you!");			
		    #}
		    #push(@tmp,trim($b_and));
		    trim($b_and);
		    $b_and=~ s/[ ]/_/xg;#clean structure name of dirty elements replacing them for underscores.
		    my @b_endpoints=split("_to_",$b_and);

		    # can we operate on all array elements at once. No we cant.
		    if ( 0 ) {
			#@b_endpoints=~ s/_/ /xg;#clean structure name of dirty elements replacing them for underscores.
			#trim(@b_endpoints);
		    } else {
			if ( scalar(@b_endpoints)>2 ) {
			    die ("Bad range! more than two endpoints");
			}
			my @range=();
			my $bname;
			use Scalar::Util qw(looks_like_number);
			for(my $be=0;$be<=$#b_endpoints;$be++){
			    $b_endpoints[$be]=~ s/_/ /xg;#clean structure name of dirty elements replacing them for underscores.
			    trim($b_endpoints[$be]);
			    #my ($base,$num) = $b_endpoints[$be] =~ /^(.*?)([0-9]+)$/x;
			    my ($base,$num) = $b_endpoints[$be] =~ /^([^0-9]+)(.*)$/x;
			    if ( looks_like_number($num) ) {
				push(@range,$num);
			    } else {
				push(@range,-1);
			    }
			    if ( defined $base ) { $bname=$base;} else { die("range error");}
			}
			#dump(@b_endpoints);
			#printf("$bname%i ",($range[0] .. $range[1]));
			$bname=~s/[ ]/_/xg;
			for(my $v=$range[0];$v<=$range[$#range];$v++){
			    if ( $v>0 ){
				push(@tmp,sprintf("%s%i",$bname,$v));
			    } else {
				push(@tmp,$bname);
			    }
			}
		    }
		}
		#print("branch: $branch_name \n");
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
		}
	    } else {
		# foreach onto_level add tnum to the tnum lookup
		push(@onto_levels,$branch_name);
		if ( ! exists($onto_hash->{"order_lookup"}->{$branch_name} ) ){
		    if( $tnum ne "" ) {
			$onto_hash->{"order_lookup"}->{$branch_name}=$tnum;
		    } else {
			$onto_hash->{"order_lookup"}->{$branch_name}="1_";
		    }
		}
	    }
	    #my $tnum="";
	    #($tnum,$branch_name)= $branch_name =~/^([0-9]*_)?(.*)$/;
	    #$tnum="" unless defined $tnum;
	    if  ( 0 
		  && $branch_name =~ /^[rmp][0-9]{1,2}(?:[^\w]+[\w]*)?$/x) {
		warn("\tAlex said to skip these structures($branch_name)");
		next;
	    }
	}
	# HERE WE SHOULD BE ABLE TO SEE PARTS
	#dump(@onto_levels);
	use List::MoreUtils qw(uniq);
	@onto_levels=uniq(@onto_levels);
	printf("\t".join("\n\t",@onto_levels)."\n");
	# onto_hash will have 4 parts.
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
    #dump($seen);
    if( scalar(@onto_error_msgs) ) {
	warn (join("\n",@onto_error_msgs));
    }
    #dump(@onto_errors);
    #dump($onto_hash);

    # NOW WE NEED TO RE_CREATE THE BRANCHES.
    # What order of operations should we use here....
    # foreach line,
    #dump($onto_hash->{"line_to_struct"});
    my $max_levels=1;
    foreach (keys( %{$o_table->{"t_line"}}) ) {
	my $o_entry=$o_table->{"t_line"}->{$_};
	#    for each superstructure of the line,
	my @super_structs=@{$onto_hash->{"line_to_struct"}->{$o_entry->{"t_line"}}};
	#dump(@super_structs);
	my $super_struct_hash;
	for my $super (@super_structs) {
	    if ( ! exists($onto_hash->{"SuperStructures"}->{$super} ) ) {
		print("Missing $super\n");
	    }
	    #
	    $super_struct_hash->{$super}=scalar(@{$onto_hash->{"SuperStructures"}->{$super}}); # this isnt right.
	    #dump($onto_hash->{"SuperStructures"}->{$super});
	}
	#dump($super_struct_hash);
	# sort keys by value, descending (use a,b for ascending, or b,a for descending).
	#my %h; $h{"test2"}=1; $h{"test1"}=60; $h{"test3"}=30; 
	#my @h_keys = sort { $h{$a} <=> $h{$b} } keys(%h);
	#dump(keys(%h));
	##("test1", "test3", "test2")
	#dump(@h_keys);
	##("test2", "test3", "test1")
	@super_structs = sort { $super_struct_hash->{$b} <=> $super_struct_hash->{$a} } keys(%$super_struct_hash);
	#dump(@super_structs);
	# 
	# use this info to bludgeon current ontology entry.
	#
	if($max_levels<scalar(@super_structs)){
	    $max_levels=scalar(@super_structs);
	}
	for(my $ln=1;$ln<=scalar(@super_structs)||exists($o_entry->{sprintf("Level_%i",$ln+1)});$ln++){
	    #if(exists($o_entry->{sprintf("Level_%i",$ln+1)}) ) {
	    if ($ln>scalar(@super_structs)) {
		delete $o_entry->{sprintf("Level_%i",$ln+1)};
	    } else {
		$o_entry->{sprintf("Level_%i",$ln)}=$onto_hash->{"order_lookup"}->{$super_structs[$ln-1]}.$super_structs[$ln-1];
	    }
	}

    }
    #    sort supers by their content count. Arrange largest to smallest, That is a good approximation of correct.
    # MAYBE we should look deeper, but lets not bother at first.
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
    #dump(%{$o_table->{'Header'}});
    $field_count=$#sorted_order;
    @{$o_table->{'Header'}}{@sorted_order}=(0 .. $field_count);
    #dump(%{$o_table->{'Header'}});
    for($ln=1;$ln<=$max_levels;$ln++){
	$o_table->{'Header'}->{sprintf("Level_%i",$ln)}=$ln+$field_count;
    }
    #dump(%{$o_table->{'Header'}});
    #dump($o_table->{"Name"});

    #exit;
    return $onto_hash;
}
