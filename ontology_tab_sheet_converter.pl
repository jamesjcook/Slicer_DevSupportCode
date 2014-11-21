#!/usr/bin/perl
# ontology tab sheet converter.pl
# used to rename structures in slicer MRML file to their complete ontology name or to their abreviation.
# uses the ontology tab sheet to generate "safe" filenames, and assumes the structures are named that in the mrml file.
# checks the hard coded label look up table to make sure the name listed there matches the name in MRML file. 
# 
# loads tab sheet and operates over every line of that file. 
#.

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

my @ontology_csv; 
my $inpath=$ARGV[0];
my @ontology_mrml;
my $inmrml=$ARGV[1];
my $outmrml=$ARGV[2];
my $rename_type=$ARGV[3];
my $outmrml_n;
if ( ! defined $inmrml ) { 
    print("ERROR: no mrml specified");
    exit;
}
if ( ! defined $rename_type ) { 
    $rename_type='clean';
}
{
    my ($n,$p,$e)=fileparts($inmrml);
    if ($rename_type eq 'clean' ) { 
	$outmrml=$p.$n."_template".$e if ( ! defined $outmrml ) ;
	$outmrml_n=$p.$n."_mhn".$e;
    } else {
	$outmrml=$p.$n."_template".$e if ( ! defined $outmrml ) ;
	$outmrml_n=$p.$n."_$rename_type".$e;
    }
    
    print("Auto mrml out will be \"$outmrml\".\n") if ( ! defined $outmrml ) ;
}

load_file_to_array($inpath,\@ontology_csv);
#my $parser=xml_read($inmrml);
#my $xml_data=xml_read($inmrml);
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
load_file_to_array("civm_rhesus_v1_verbose_labels_lookup_a.txt",\@color_table);
my $color_table_out="civm_rhesus_v1_verbose_labels_lookup_a_template.txt";
@ontology_mrml=mrml_find_by_id($xml_data,".*");
#display_complex_data_structure(\@refs,'  ')

print("colortable ".($#ontology_csv+1)." lines loaded\n");
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
if($#col_headers==-1 && $#parts >= 5){
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
#     @parts=split("\t",$line);
    #
    @parts = $line =~ /([^\t]+)/gx;
    chomp(@parts);
    #
    #print(join(':',@parts)."\n");
    if ( 0 ) { 
	#print("$#parts");
	#print("$#parts:$line\n");
    } elsif ( $#parts >= 6) {  # say important line starts with "num_procs" ( it does) 
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
	    my $s_path='Static_Render/ModelTree';

	    
	    my $ref=\%onto_hash;
	    #for(my $pn=$#parts;$pn>=0;$pn--){
	    for(my $pn=0;$pn<=$#parts;$pn++){# proces the different levels of ontology, get the different ontology names, create a path to save the structure into.
		# 
		my $tree_name=$parts[$pn];#meta structure name
		#$tree_name=~ s/[,\/#]/_/xg;#clean structure name of dirty elements replaceing them for underscores.
		$tree_name=~ s/[,\/# ]/_/xg;#clean structure name of dirty elements replaceing them for underscores.
		$s_path="$s_path/$tree_name"; #add cleanname to subpath.
		if ( ! defined (@{$l_1{$tree_name}}) ) { 
		    @{$l_1{$tree_name}}=();
		    #print("\n---ON-level:$pn-UNDEF:$tree_name.---\n");
		}
		if ( ! -d $s_path ){
		    print("mkdir $s_path\n");
		    if ( $do_unsafe) {
		    mkdir ($s_path);
		    }
		}
		push(@{$l_1{$tree_name}},$value);
		
		if ( ! defined $ref->{$tree_name}) {# clever way to build hierarchy hash on fly. 
		    print("$tree_name not there, adding ... \n") if ($debug_val>=75);
		    $ref->{$tree_name}={}; 
		}
		$ref=$ref->{$tree_name}; # this is our destination point for our structure once we've ensured the whole hierarchy before it is built.
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
		my $file_name="v1_${value}_${alt_name}";
		my $file_dest='Static_Render/ModelTree/'.join('/',@parts)."/$file_name.vtk";
		$file_dest="$s_path/$file_name.vtk";
		$file_dest=~ s/[ ]/_/gx;
		my $file_src="Static_Render/ModelTree/$file_name.vtk";
		my @c_path=($file_src,$file_dest);
		if ( ! -f $file_dest) {
		    if ( -e $file_src ) { 
			push(@c_name,$file_name.".vtk");
			print("mv $file_src $file_dest\n");
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
		# check colortable for name.
		### 
		for(my $ct_i=0;$ct_i<=$#color_table;$ct_i++) { 
		    my $cte=$color_table[$ct_i];
		    #print($cte);
		    if ( $cte !~ /^#.*/ ) {
			my @ct_entry=split(' ',$cte);
			#print("ct:".join(" ",@ct_entry)."\n");
			if ( $value == $ct_entry[0]&&  $#ct_entry>=4) { 
			    if($alt_name ne $ct_entry[1]) {
				print("COLORTABLE NAME FAILURE($value) generated : $alt_name, colortable $ct_entry[1]\n");
			    }
			    $ct_entry[1]="v1_${value}_$alt_name";
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
		#   get the modelhieracry that controls our location by looking at associateNodeRef = our id.
		# rename that modelhierarcy to alt_name,this didnt work, try again using v1_value_alt_name
		@mrml_nodes=mrml_find_by_name($xml_data,$alt_name,"Model");
		
		for(my $ri=0;$ri<$#mrml_nodes;$ri++){
		    if ( mrml_node_diff($mrml_nodes[$ri],$mrml_nodes[$ri+1]) ) { 
			warn("more nodes found than expected!($#mrml_nodes)".join(@mrml_nodes,' ')."\n");
		    }   
		}
		my $node=$mrml_nodes[0];
		#display_complex_data_structure($node);
		my $node_id=$node->{'id'};
		if ( defined $node_id  ) {
		    my @mrmls_found=mrml_attr_search($xml_data,"associatedNodeRef",$node_id."\$","ModelHierarchy");
		    #print("found ".($#mrmls_found+1)." references to this node\n");
		    foreach my $mrml_node ( @mrmls_found){
			#print("change node $mrml_node->{id} $mrml_node->{name} to $alt_name\n");
			if($rename_type eq 'clean' ){
			    $mrml_node->{"name"}="$alt_name";
			} elsif($rename_type eq 'modelfile' ){
			    $mrml_node->{"name"}="v1_${value}_$alt_name";
			    $node->{"name"}="v1_${value}_$alt_name";
			} elsif( $rename_type eq 'ontology')  {
			    $mrml_node->{"name"}="$name";
			    $node->{"name"}="$name";
			} elsif( $rename_type eq 'abrev')  { 
			    $mrml_node->{"name"}="$abrev";
			    $node->{"name"}="$abrev";
			} else { 
			    $mrml_node->{"name"}="v1_${value}_$alt_name";
			    $node->{"name"}="v1_${value}_$alt_name";
			}
		    }
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
	    my $file_name="v1_${value}_${alt_name}";
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
    #print("(v1_".join('_|v1_',@{$l_1{$kn}}),")\n");#elements regex
}
#display_complex_data_structure(\%onto_hash,'  ',0,'noleaves'); # noleaves doenst exactly work because some trees have twigs foreach leaf
#display_complex_data_structure(\%onto_hash);

#xml_write($xml_data,$outmrml)

   

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
