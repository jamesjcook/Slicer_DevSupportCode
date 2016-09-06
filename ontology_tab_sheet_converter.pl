#!/usr/bin/perl
# ontology tab sheet converter.pl
# used to rename structures in slicer MRML file to their complete ontology name or to their abreviation.
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

my @ontology_csv; 
my $inpath=$ARGV[0];
my @ontology_mrml;
my $inmrml=$ARGV[1];
my $outmrml=$ARGV[2];
my $rename_type=$ARGV[3];
my $model_prefix="Model_";
$debug_val=25;
my $outmrml_n;
if ( ! defined $inmrml ) { 
    print("specifiy at least csv, mrml.optionally specify output and rename type(clean|ontology|abrev) ERROR: no mrml specified");
    exit;
}
if ( ! defined $rename_type ) { 
    $rename_type='clean';
}
if ( 1 ) 
{
    my ($n,$p,$e)=fileparts($inmrml);
    if ($rename_type eq 'clean' ) { 
	$outmrml=$p.$n."_template".$e if ( ! defined $outmrml ) ;
	$outmrml_n=$p.$n."_mhn".$e;
    } else {
	$outmrml=$p.$n."_template".$e if ( ! defined $outmrml ) ;
	$outmrml_n=$p.$n."_$rename_type".$e;
    }
    
    print("Auto mrml out will be \"$outmrml\".\n") ;
}

load_file_to_array($inpath,\@ontology_csv);
#my $parser=xml_read($inmrml);
#my $xml_data=xml_read($inmrml);
#print("THE END\n");exit;
my ($xml_data,$xml_parser)=xml_read($inmrml,'giveparser');

#my $xml_txt=$parser->ToXML("");
#my $xml_txt=xml_to_string($xml_data,$inmrml,$outmrml);
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
#write_array_to_file($outmrml,\@mrml_txt);


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

# print("open $inpath\n");
# if (open SESAME, $inpath) { 
#     @ontology_csv = <SESAME>; 
#     close SESAME; 
#     chomp(@ontology_csv);
# } else { 
#     print STDERR "Unable to open file to read\n"; 
#     return (0); 
# } 

# print("open $inmrml\n");
# if (open SESAME, $inmrml) { 
#     @ontology_mrml = <SESAME>; 
#     close SESAME; 
#     chomp(@ontology_mrml);
# } else { 
#     print STDERR "Unable to open file to read\n"; 
#     return (0); 
# } 

my @color_table;
#load_file_to_array("civm_rhesus_v1_verbose_labels_lookup_a.txt",\@color_table);
#load_file_to_array("ex_data_and_xml/ex_color_table.txt",\@color_table);
#my $color_table_out="ex_data_and_xml/ex_color_table_out.txt";

load_file_to_array("ex_color_table.txt",\@color_table);
my $color_table_out="ex_color_table_out.txt";
@ontology_mrml=mrml_find_by_id($xml_data,".*");
#display_complex_data_structure(\@refs,'  ')

print("color_table ".($#ontology_csv+1)." lines loaded\n");
print("ontology ".($#ontology_csv+1)." lines loaded\n");
print("mrml ".($#ontology_mrml+1)." nodes loaded\n");
my @parts;
my @col_headers;
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
@parts = $line =~ /([^\t]+)/gx;
if ( $#parts < 3) {
    warn("Used commas instead of tabs, You better have clean names.");
    @parts = $line =~ /([^,]+)/gx;
}
if($#col_headers==-1 && $#parts >= 3){
    print("col_headers assign:".join(" ",@parts)."\n");
    @col_headers=@parts;
}
my @d_abrev;   #input dirty abreviaion files found
my @d_a_found; # output dirty abreviaions files found
my @d_name;    #intput dirty name files found
my @d_n_found; # output dirty name files found
my @c_name;    #input clean name files found
my @c_n_found; # output clean name files found
my $do_unsafe=0;
my ($process_abrev_names,$process_full_names)=(0,0);
my @model_hierarchy_nodes=mrml_find_by_name($xml_data,".*","ModelHierarchy");# should return only ModelHierarchyNodes
foreach $line (@ontology_csv) {
    @parts = $line =~ /([^\t]+)/gx;
    if ( $#parts < 3) {
	warn("Used commas instead of tabs, You better have clean names.") unless ($debug_val<45);
	@parts = $line =~ /([^,]+)/gx;
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
		my $a_name=$parts[$pn];#$col_headers[$pn]
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

	my $name=shift(@parts);
	my $abrev=shift(@parts);
	my $value=pop(@parts);
	my ($a_fn,$c_fn,$f_fn)=('','','');
	my (@a_path,@s_path,@f_path)=((),(),());
# 		if ( ! -d './MoldelTree/'.join('/',@parts) ){
# 		    print("mkdir './ModelTree/'.join('/',@parts)\n");
# 		}
	if ( 1) { 
	    #print("#$abrev:$name\n");
	    my $s_path='Static_Render/LabelModels';

	    
	    my $ref=\%onto_hash;
	    
	    my $rootHierarchyNodeID="vtkMRMLModelHierarchyNode1";#vtkMRMLHierarchyNode1"
	    my $parent_ref={};
	    my @vtkMRMLHierarchyNodes=mrml_attr_search($xml_data,"id",$rootHierarchyNodeID."\$","ModelHierarchy");
	    # I think this'll find two nodes, One ModelHierarchy directly attahced to the MRML hash,
	    # and another directly attached to SceneView, which is attached to MRML. As far as i can tell these are the same.
	    # There is just an inherrent inefficiency in the way slicer stores its information.
	    #$mrml_node->{"name"}
	    
	    if (  $#vtkMRMLHierarchyNodes>=0 ) {#there is at least one node.
		$parent_ref=$vtkMRMLHierarchyNodes[0];
		print("Found $#vtkMRMLHierarchyNodes Hierarchy roots.\n");
	    } else {
		warn("No root nodes!!!!");
	    }
	    #my @vtkMRMLModelDisplayNodes=mrml_attr_search($xml_data,"id",$parent_ref->{"displayNodeID"}."\$","ModelDisplay");# this may not be what i'm looking to do. 
	    my $parent_hierarchy_node_id=$rootHierarchyNodeID;
	    my $hierarchy_template = \%{clone $parent_ref};
	    #dump($hierarchy_template);
	    #sleep_with_countdown(3);
	    my $sort_val=$#{$xml_data->{"MRML"}->{"ModelHierarchy"}};
	    $hierarchy_template->{"sortingValue"}=$sort_val;
	    #for(my $pn=$#parts;$pn>=0;$pn--){
	    for(my $pn=0;$pn<=$#parts;$pn++){# proces the different levels of ontology, get the different ontology names, create a path to save the structure into.
		# 
		my $tree_name=$parts[$pn];#meta structure name
		my $tnum="";
		($tnum,$tree_name)= $tree_name =~/^([0-9]*_)?(.*)$/;
		$tnum="" unless defined $tnum;
		#$tree_name=~ s/[,\/#]/_/xg;#clean structure name of dirty elements replaceing them for underscores.
		$tree_name=~ s/[,\/# ]/_/xg;#clean structure name of dirty elements replaceing them for underscores.
		$s_path="$s_path/$tnum$tree_name"; #add cleanname to subpath.
		if ( ! defined (@{$l_1{$tnum.$tree_name}}) ) { 
		    @{$l_1{$tnum.$tree_name}}=();
		    #print("\n---ON-level:$pn-UNDEF:$tnum.$tree_name.---\n");
		}
		if ( ! -d $s_path ){
		    print("mkdir $s_path\n") if ($debug_val>=45);
		    if ( $do_unsafe) {
		    mkdir ($s_path);
		    }
		}
		push(@{$l_1{$tnum.$tree_name}},$value);
		
		if ( ! defined $ref->{$tnum.$tree_name}) {# clever way to build hierarchy hash on fly. The hierarchy has is just a holder for the structure.
		    print("$tree_name not there, adding ... \n") if ($debug_val>=25);
		    $ref->{$tnum.$tree_name}={};
		    # update template with values for this structure.
		    $hierarchy_template->{"name"}=$tree_name;
		    $hierarchy_template->{"id"}=$tnum.$tree_name;
		    $hierarchy_template->{"parentNodeRef"}=$parent_hierarchy_node_id;
		    $hierarchy_template->{"sortingValue"}=$hierarchy_template->{"sortingValue"}+1;
		    # now add the template to MRML->ModelHierarchy and MRML->SceneView->ModelHierarchy
		    #push(@{$xml_data->{"MRML"}->{"ModelHierarchy"}},%{clone $hierarchy_template});
		    push(@{$xml_data->{"MRML"}->{"ModelHierarchy"}},\%{clone $hierarchy_template});
		    push(@{$xml_data->{"MRML"}->{"SceneView"}->{"ModelHierarchy"}},\%{clone $hierarchy_template});
		    #@vtkMRMLHieraryNodes=mrml_attr_search($xml_data,"associatedNodeRef",$rootHierarchyNodeID."\$","ModelHierarchy");
		    # if the ref dont exist, we add it... hmm how/when do we set the type to vtkMRMLModelHierarchyNode?
		    #printf("--template_val--");
		    #dump($hierarchy_template);
		    #dump($xml_data->{"MRML"}->{"ModelHierarchy"});

		    
		}
		$ref=$ref->{$tnum.$tree_name}; # this is our destination point for our structure once we've ensured the whole hierarchy before it is built.
		$parent_hierarchy_node_id=$tnum.$tree_name;
	    }



	    {# safe but ugly name_handle
		my @mrml_nodes;
		my $alt_name=$name;
		$alt_name=~ s/,[ ]/CMA/gx;
		$alt_name=~ s/[ ]/SPC/gx;
		$alt_name=~ s/,/CMA/gx;
		$alt_name=~ s/\//FSLASH/gx;
		$alt_name=~ s/\+/PLS/gx;
		#$alt_name=~ s/\(/\\(/gx;
		#$alt_name=~ s/\)/\\)/gx;
		$c_fn=$alt_name;
		my $file_name="$model_prefix${value}_${alt_name}";
		my $file_dest='Static_Render/ModelTree/'.join('/',@parts)."/$file_name.vtk";
		$file_dest="$s_path/$file_name.vtk";
		$file_dest=~ s/[ ]/_/gx;
		my $file_src="Static_Render/LabelModels/$file_name.vtk";
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
		$ref->{$alt_name}=$value;

		###
		# check color_table for name.
		### 
		for(my $ct_i=0;$ct_i<=$#color_table;$ct_i++) { 
		    my $cte=$color_table[$ct_i];
		    #print($cte);
		    if ( $cte !~ /^#.*/ ) {
			my @ct_entry=split(' ',$cte);
			#print("ct:".join(" ",@ct_entry)."\n");
			if ( $value == $ct_entry[0]&&  $#ct_entry>=4) { 
			    if($alt_name ne $ct_entry[1]) {
				print("COLOR_TABLE NAME FAILURE($value) generated : $alt_name, color_table $ct_entry[1]\n");
			    }
			    #$ct_entry[1]="$model_prefix${value}_$alt_name";
			    $ct_entry[1]="$alt_name";
			    #$color_table[$ct_i]=join(@ct_entry,' ');
			    $color_table[$ct_i]=join(' ',@ct_entry)."\n";
			}
		    }
		}
		


		###
		# fix the name in our xml_out.
		###
		# find any mrml nodes with name = alt name 
		# using the id from the model node,
		#   get the modelhierarchy that controls our location by looking at associateNodeRef = our id.
		# rename that modelhierarchy to alt_name,this didnt work, try again using v1_value_alt_name
		@mrml_nodes=mrml_find_by_name($xml_data,$alt_name,"Model");
		
		for(my $ri=0;$ri<$#mrml_nodes;$ri++){
		    if ( mrml_node_diff($mrml_nodes[$ri],$mrml_nodes[$ri+1]) ) { 
			warn("more nodes found than expected!($#mrml_nodes)".join(@mrml_nodes,' ')."\n");
			sleep_with_countdown(3);
		    }   
		}
		my $node=$mrml_nodes[0];
		#display_complex_data_structure($node);
		my $node_id=$node->{"id"};
		if ( defined $node_id  ) {
		    my @mrmls_found=mrml_attr_search($xml_data,"associatedNodeRef",$node_id."\$","ModelHierarchy");
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
			} elsif( $rename_type eq 'abrev')  { 
			    $mrml_node->{"name"}="$abrev";
			    $node->{"name"}="$abrev";
			} else { 
			    $mrml_node->{"name"}="$model_prefix${value}_$alt_name";
			    $node->{"name"}="$model_prefix${value}_$alt_name";
			}
			$mrml_node->{"parentNodeRef"}=$parent_hierarchy_node_id;
		    }
		} else {
		    warn("OHh NOOOO node id not set ! Sleeping a bit while you look at this!");
		    dump($node);
		    sleep_with_countdown(15);
		}
	    }


	    if ( $process_abrev_names ) { #abrev name_handle
	    my $alt_name=$abrev;
	    $alt_name=~ s/[ ]/_/gx;
	    $alt_name=~ s/,/_/gx;
	    $alt_name=~ s/\//_/gx;
	    $alt_name=~ s/\+/_/gx;
	    #$alt_name=~ s/\(/\\(/gx;
	    #$alt_name=~ s/\)/\\)/gx;
	    $a_fn=$alt_name;
	    my $file_name="$model_prefix${value}_${alt_name}";
	    my $file_dest="Static_Render/LabelModels_abrev/$file_name.vtk";
	    my $file_src="Static_Render/ModelTree/$file_name.vtk";
	    @a_path=($file_src,$file_dest);
	    if ( ! -f $file_dest) {
		if ( -e $file_src ) { 
		    push(@d_abrev,$file_name.".vtk");
		    print("mv $file_src $file_dest\n");
		    if ( $do_unsafe ) {
		    rename($file_src, $file_dest);
		    }
		} else {
		    print ("\t #missing $file_src\n");
		}

	    } else {
		push(@d_a_found,$file_dest);
	    }
	    }
	    if ( $process_full_names ) {# full name_handle
	    my $alt_name=$name;
	    #$alt_name=~ s/[ ]/_/gx;
	    $alt_name=~ s/\/[^\s]+//gx;
	    $alt_name=~ s/,[ ]//gx;
	    $alt_name=~ s/,//gx;

	    $alt_name=~ s/\+//gx;
	    #$alt_name=~ s/\(/\\(/gx;
	    #$alt_name=~ s/\)/\\)/gx;
	    $f_fn=$alt_name;
	    my $file_name="${alt_name}";
	    my $file_dest="Static_Render/LabelModels_full_names/$file_name.vtk";
	    my $file_src="Static_Render/ModelTree/$file_name.vtk";
	    my @f_path=($file_src,$file_dest);
	    if ( ! -f $file_dest) {
		if ( -e $file_src ) { 
		    push(@d_name,$file_name.".vtk");
		    print("mv $file_src $file_dest\n");
		    if ( $do_unsafe ) {
		    rename($file_src, $file_dest);
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

    }  elsif ( $#parts == 5) { 
	print(".....");
    } elsif ( $#parts == 4) {
	print("....");
    } elsif ( $#parts == 3) {
	print("...");
    } elsif ( $#parts == 2) {
	print("..");
    } elsif ( $#parts == 1) {
	print(".");
    } elsif ( $#parts == 0) { 
	print("0");
    } elsif ( $#parts == -1) { 
	print("-");
    }
    #for cn=1:$#col_headers,col_header,push onto hash{colheader(cn)},parts(cn)
    #print  SESAME_OUT $line;  # write out every line modified or not 
} 

print("PROCESS SUMMARY\n".
      "\ttotal_possiblities:$#ontology_csv, \n".
      "\tcandidates available and unprocessed, \n".
      "\t#unprocessed clean_names:$#c_name,\n".
      "\t#unprocessed dirty_names:$#d_name,\n".
      "\t#unprocessed dirty_abrevs:$#d_abrev\n".
      "candidates found at dest\n".
      "clean_names:$#c_n_found,\n".
      "dirty_names:$#d_n_found,\n".
      "dirty_abrevs:$#d_a_found\n");
print(join(':',@col_headers)."\n");
print('larger_level_structures >');
my @list=keys(%l_1);
for my $kn (@list)  {
    my @s_list=@{$l_1{$kn}};
    #print("\t$kn:$#{$l_1{$kn}}\n");
    #print("($model_prefix".join('_|$model_prefix',@{$l_1{$kn}}),")\n");#elements regex
}
#display_complex_data_structure(\%onto_hash,'  ',0,'noleaves'); # noleaves doenst exactly work because some trees have twigs foreach leaf
#display_complex_data_structure(\%onto_hash);

#xml_write($xml_data,$outmrml)
printf("ontology built\n");
dump(%onto_hash);
#dump(%l_1);
sleep_with_countdown(3);
   

mrml_to_file($xml_data,'  ',0,'pretty','',$outmrml_n);
if( $rename_type eq 'modelfile' || $rename_type eq 'ontology' || $rename_type eq 'abrev') {
    mrml_clear_nodes($xml_data,("ModelHierarchy","ModelDisplay","Version", "UserTags"));
    mrml_to_file($xml_data,'  ',0,'pretty','',$outmrml);
    write_array_to_file($color_table_out,\@color_table);
}#$rename_type eq 'clean' ||
#close SESAME_OUT; 

# when you are sure this is working add... 
# rename $outpath, $inpath;  # destroys inpath, change name of file f

#    $cmd = "copy $ARGV[0] $ARGV[0].bak";
#    system($cmd);
#    $outpath=$ARGV[0].bak;
