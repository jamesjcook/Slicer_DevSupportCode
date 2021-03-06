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

die "This code is obsolete.";

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
#use xml_read qw(xml_read);
use Data::Dump qw(dump);
use Clone qw(clone);
use Getopt::Std;# qw(getopts);
use File::Basename;
our %opt;
if (! getopts('c:h:m:o:t:', \%opt||$#ARGV>=0)) {
    die "$!: Option error, valid options, -h hierarchy.csv -m input_mrml.mrml -c colortable.txt (-o output.mrml)? (-t (clean|Abbrev|modelfile|ontology))?";
}
#-h hierarchy.csv
#-m inmrml.mrml
#-c colortabl.txt
#-o output.mrml

my @ontology_csv; 
#my $ontology_inpath=$ARGV[0];
my $ontology_inpath=$opt{"h"};#$opt{""};
my @mrml_nodes_loaded;
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
if ( ! defined $p_mrml_in ) { 
    print("specifiy at least csv, mrml.optionally specify output and rename type(clean|ontology|Abbrev) ERROR: no mrml specified");
    exit;
}
if ( ! defined $rename_type ) { 
    $rename_type='clean';
}
if ( 1 ) 
{
    my ($n,$p,$e)=fileparse($p_mrml_in);
    if ($rename_type eq 'clean' ) { 
	$p_mrml_out=$p.$n."_mhn".$e if ( ! defined $p_mrml_out ) ;
	$p_mrml_out_template=$p.$n."_template".$e ;
    } else {
	$p_mrml_out_template=$p.$n."_template".$e;
	$p_mrml_out=$p.$n."_$rename_type".$e  if ( ! defined $p_mrml_out ) ;
    }
    
    print("Auto mrml out will be \"$p_mrml_out_template\".\n") ;
}

my ($Tn,$Tp,$Te)=fileparse($p_color_table_in);
my $p_color_table_out=$Tp.$Tn."_out".$Te;
my @color_table_lines;
#load_file_to_array("civm_rhesus_v1_verbose_labels_lookup_a.txt",\@color_table_lines);
#load_file_to_array("ex_data_and_xml/ex_color_table_lines.txt",\@color_table_lines);
#my $color_table_out="ex_data_and_xml/ex_color_table_out.txt";

load_file_to_array($p_color_table_in,\@color_table_lines);
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
my $c_table;
$c_table->{"Structure"}={};
$c_table->{"Abbrev"}={};
$c_table->{"Name"}={};
# this loop sets up a nice comprehensive lookup structure for the color table.
# for the primary keys of "structure Abbreviation and name", make a hash of primary key to the colortable info for each color table entry
foreach my $c_line (@color_table_lines) {
    if ( $c_line !~ /^#.*/ ) {# if not comment.
	my @ct_entry=split(' ',$c_line);
	# color table is form of,
	# VALUE NAME RED GREEN BLUE ALPHA
	
	# the expected format of our colortable comes from the avizo name format of alex. 
	# the names used in avizo were "_?abbreviation__(_?)fullterribly_long_structure_name"
	# some names add additional instances of double underscore. its uncertain what that was about. 
	my ($c_Abbrev,$c_name)= $ct_entry[1] =~/^_?(.+?)(?:___?(.*))$/;
	if(not defined $c_Abbrev) {
	    use List::Util qw(first max maxstr min minstr reduce shuffle sum);
	    my $maxn=min(20,length($ct_entry[1]));
	    $c_Abbrev=substr($ct_entry[1],0,$maxn);
	}
	if(not defined $c_name) {
	    $c_name=$c_Abbrev;
	}
	#dump(@ct_entry[0,2..5]);
	# basic lookups. 
	#$c_table->{"Structure"}->{"$ct_entry[1]"}=[@ct_entry[0,2..5]];
	#$c_table->{"Abbrev"}->{$c_Abbrev}=[@ct_entry[0,2..5]];
	#$c_table->{"name"}->{$c_name}=[@ct_entry[0,2..5]];
	if ( 1 ) {
	    #my @stv{qw(Structure Abbrev name)}=($ct_entry[1], $c_Abbrev, $c_name);
	    #my @stv{qw[Structure Abbrev name]}=($ct_entry[1], $c_Abbrev, $c_name);
	    #my %stv=qw(Structure Abbrev name)[$ct_entry[1], $c_Abbrev, $c_name];
	    #my @stv=qw(Structure Abbrev name)[$ct_entry[1], $c_Abbrev, $c_name];
	    my %stv;
	    @stv{qw(Structure Abbrev Name)}=($ct_entry[1], $c_Abbrev, $c_name);
	    #dump(\%stv);
	    #exit;
	    # advanced lookups.
	    if ( 1 ) {
		
		my $c_t_e = {
		    "Value" => $ct_entry[0], 
		    "c_R" => $ct_entry[2],
		    "c_G" => $ct_entry[3],
		    "c_B" => $ct_entry[4],
		    "c_A" => $ct_entry[5],
		};
		# combine hash overwriting values using this example. My usage and setup here is rather complicated.
		#my %t = %target;
		#@t{keys %source} = values %source;
		@{$c_t_e}{(keys %stv)} =values %stv;
		#delete($c_table->{$sub_tree}->{$stv{$sub_tree}}->{$sub_tree});

		for my $sub_tree (keys %stv) {
		    $c_table->{$sub_tree}->{$stv{$sub_tree}}=$c_t_e;
#		    last;
		}
	    } else {
	    for my $sub_tree (keys %stv) {
		$c_table->{$sub_tree}->{$stv{$sub_tree}} = {
		    "Value" => $ct_entry[0], 
		    "c_R" => $ct_entry[2],
		    "c_G" => $ct_entry[3],
		    "c_B" => $ct_entry[4],
		    "c_A" => $ct_entry[5],
		};
		# combine hash overwriting values using this example. My usage and setup here is rather complicated.
		#my %t = %target;
		#@t{keys %source} = values %source;
		@{$c_table->{$sub_tree}->{$stv{$sub_tree}}}{(keys %stv)} =values %stv;
		delete($c_table->{$sub_tree}->{$stv{$sub_tree}}->{$sub_tree});
	    }}
	}
    }
}


#dump($c_table);
my $Tr;
#$Tr=$c_table->{"Abbrev"};
#dump($Tr);
#$Tr=$c_table->{"Name"};
#dump($Tr);
#$Tr=$c_table->{"Structure"};
#dump($Tr);

#exit;

load_file_to_array($ontology_inpath,\@ontology_csv);
#my $parser=xml_read($p_mrml_in);
#my $xml_data=xml_read($p_mrml_in);
#print("THE END\n");exit;
my ($xml_data,$xml_parser)=xml_read($p_mrml_in,'giveparser');

#my $xml_txt=$parser->ToXML("");
#my $xml_txt=xml_to_string($xml_data,$p_mrml_in,$p_mrml_out_template);
#display_complex_data_structure($parser,'   ');

#display_complex_data_structure($xml_data,'   ');
#display_complex_data_structure($xml_parser);
#print($xml_txt."\n");


# my $xml_eval=dump($xml_data,' ');
# my $xml_data_c;
# eval("\$xml_data_c=$xml_eval");

### massive memory use because returning the string: (
# should be adjusted to string refing.
#my $xml_string=mrml_to_string($xml_data);
#print($xml_string);
#my @mrml_txt=split("\n",$xml_string);
#write_array_to_file($p_mrml_out_template,\@mrml_txt);


if(0){
    dump($xml_parser);
}
if(0){
    dump($xml_data);
}
#exit;
#my $xml_data=mrml_find_by_name($xml_data->{"MRML"},"whiteSPCmatter","ModelHierarchy");
#my $xml_data=mrml_find_by_name($xml_data,"whiteSPCmatter","ModelHierarchy");
#my $xml_data=mrml_find_by_name($xml_data,"whiteSPCmatter");#,"ModelHierarchy");
#display_complex_data_structure($xml_data,'  ','pretty');
#exit();

@mrml_nodes_loaded=mrml_find_by_id($xml_data,".*"); # could i just scalar that for how i'm doing things?
#display_complex_data_structure(\@refs,'  ')

print("color_table ".($#ontology_csv+1)." lines loaded\n");
print("ontology ".($#ontology_csv+1)." lines loaded\n");
print("mrml ".($#mrml_nodes_loaded+1)." nodes loaded\n");
my @parts;
my @ontology_sheet_columns;
my %ontology_header_index=();
my @ontology_label_fields=();
my @ontology_color_fields=();
my %l_1;
my %onto_hash=();
# my %l_2;
# my %l_3;
# my %l_4;
# my %l_5;



###
# Process ontology CSV file.
###
# determine the different file names and paths per each convention.
# move files into appropriate destination place, from starting place/places.

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
my $do_unsafe=0;
my ($process_Abbrev_names,$process_full_names)=(0,0);
#my @model_hierarchy_nodes=mrml_find_by_name($xml_data,".*","ModelHierarchy");# should return only ModelHierarchyNodes
# not that i'm using this variabl, so i'm commenting it out.



my $rootHierarchyNodeID="vtkMRMLModelHierarchyNode1";#vtkMRMLHierarchyNode1"
my $rootHierarchyNode={};
my @vtkMRMLHierarchyNodes=mrml_attr_search($xml_data,"id",$rootHierarchyNodeID."\$","ModelHierarchy");
# I think this'll find two nodes, One ModelHierarchy directly attahced to the MRML hash,
# and another directly attached to SceneView, which is attached to MRML. As far as i can tell these are the same.
# There is just an inherrent inefficiency in the way slicer stores its information.
#$mrml_node->{"name"}
if (  $#vtkMRMLHierarchyNodes>=0 ) {#there is at least one node.
    $rootHierarchyNode=$vtkMRMLHierarchyNodes[0];
    print("Found ".scalar @vtkMRMLHierarchyNodes." Hierarchy roots.\n");
} else {
    warn("No root nodes!!!!");
}



foreach $line (@ontology_csv) {
    chomp($line);
    @parts = $line =~ /([^\t]+)/gx;# WHY DIDNT I USE SPLIT!!!!!
    if ( $#parts < 3) {
	warn("Used commas instead of tabs, You better have clean names.") unless ($debug_val<45);
	@parts = $line =~ /([^,]+)/gx;# WHY DIDNT I USE SPLIT!!!!!
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


	    #####
	    #  THIS CODE MOVED HIGHER
	    #####
	    #my $rootHierarchyNodeID="vtkMRMLModelHierarchyNode1";#vtkMRMLHierarchyNode1"
	    #my @vtkMRMLHierarchyNodes=mrml_attr_search($xml_data,"id",$rootHierarchyNodeID."\$","ModelHierarchy");
	    # I think this'll find two nodes, One ModelHierarchy directly attahced to the MRML hash,
	    # and another directly attached to SceneView, which is attached to MRML. As far as i can tell these are the same.
	    # There is just an inherrent inefficiency in the way slicer stores its information.
	    #if (  $#vtkMRMLHierarchyNodes>=0 ) {#there is at least one node.
	    #$parent_ref=$vtkMRMLHierarchyNodes[0];
	    #print("Found ".scalar @vtkMRMLHierarchyNodes." Hierarchy roots.\n");
	    #} else {
	    #warn("No root nodes!!!!");
	    #}

	    my @vtkMRMLModelDisplayNodes=mrml_attr_search($xml_data,"id",$parent_ref->{"displayNodeID"}."\$","ModelDisplay");# this may not be what i'm looking to do.
	    my $model_display_template = \%{clone $vtkMRMLModelDisplayNodes[0]};
	    my $parent_hierarchy_node_id=$rootHierarchyNodeID;
	    my $hierarchy_template = \%{clone $parent_ref};
	    #dump($hierarchy_template);
	    #sleep_with_countdown(3);
	    my $sort_val=$#{$xml_data->{"MRML"}->{"ModelHierarchy"}}; # current count of modelhierarchy nodes
	    #my $display_node_num=$#{$xml_data->{"MRML"}->{"ModelDisplay"}};# was going to just set names like slicer does, but that would assume that slicer's vtkrMRMLModelDisplayNodes start numbering at 1/0. That is not a safe assumption. 
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
		    mkdir ($s_path);
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
		    #push(@{$xml_data->{"MRML"}->{"ModelHierarchy"}},%{clone $hierarchy_template});
		    push(@{$xml_data->{"MRML"}->{"ModelHierarchy"}},\%{clone $hierarchy_template});
		    push(@{$xml_data->{"MRML"}->{"ModelDisplay"}},\%{clone $model_display_template}); 
		    push(@{$xml_data->{"MRML"}->{"SceneView"}->{"ModelHierarchy"}},\%{clone $hierarchy_template});
		    push(@{$xml_data->{"MRML"}->{"SceneView"}->{"ModelDisplay"}},\%{clone $model_display_template});
		    #@vtkMRMLHieraryNodes=mrml_attr_search($xml_data,"associatedNodeRef",$rootHierarchyNodeID."\$","ModelHierarchy");
		    # if the ref dont exist, we add it... hmm how/when do we set the type to vtkMRMLModelHierarchyNode?
		    #printf("--template_val--");
		    #dump($hierarchy_template);
		    #dump($xml_data->{"MRML"}->{"ModelHierarchy"});
		    #dump($xml_data->{"MRML"}->{"SceneView"}->{"ModelHierarchy"});
		    #dump($xml_data->{"MRML"}->{"ModelDisplay"});
		    #dump($xml_data->{"MRML"}->{"SceneView"}->{"ModelDisplay"});
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
	    
	    @mrml_nodes=mrml_find_by_name($xml_data,$alt_name,"Model");
	    if ( scalar @mrml_nodes !=1 ){
		printf("MISSING $alt_name:".scalar @mrml_nodes."\n");
		@mrml_nodes=mrml_find_by_name($xml_data,($model_prefix.$value."_"),"Model"); 
		printf("\t ${model_prefix}${value}_:".scalar @mrml_nodes."\n");
		if ( scalar @mrml_nodes !=1 ){
		    @mrml_nodes=mrml_find_by_name($xml_data,($model_prefix.'[0-9]+_'.$Abbrev."__"),"Model");
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
		my @mrmls_found=mrml_attr_search($xml_data,"associatedNodeRef",$node_id."\$","ModelHierarchy");
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
	    my @s_nodes=mrml_attr_search($xml_data,"id",$storage_node_id."\$","ModelStorage");
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

#dump($xml_data->{"MRML"}->{"ModelHierarchy"});
#dump($xml_data->{"MRML"}->{"ModelDisplay"});
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

#xml_write($xml_data,$p_mrml_out_template)
printf("ontology built\n");
dump(%onto_hash);
#dump(%l_1);
sleep_with_countdown(3);
   

mrml_to_file($xml_data,'  ',0,'pretty','',$p_mrml_out);
if( $rename_type eq 'modelfile' || $rename_type eq 'ontology' || $rename_type eq 'Abbrev') {
    mrml_clear_nodes($xml_data,("ModelHierarchy","ModelDisplay","Version", "UserTags"));
    mrml_to_file($xml_data,'  ',0,'pretty','',$p_mrml_out_template);
    write_array_to_file($p_color_table_out,\@color_table_lines);
}#$rename_type eq 'clean' ||
#close SESAME_OUT; 

# when you are sure this is working add... 
# rename $outpath, $ontology_inpath;  # destroys ontology_inpath, change name of file f

#    $cmd = "copy $ARGV[0] $ARGV[0].bak";
#    system($cmd);
#    $outpath=$ARGV[0].bak;
