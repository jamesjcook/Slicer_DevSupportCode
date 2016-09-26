#!/usr/bin/perl
# tract_mrml_settings_copy.pl
# given an object name copy a list of attributes to other objects of same type.
# usage, 
# tract_mrml_settings_copy.pl  3n_l,colorbyline,percentage[=10] in.mrml [out.mrml]

# open mrml
# find template_object by name
# for each tract display?(object)
# copy settings.



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
#$debug_val=100;
#obj_template_name
#obj_attrib
my ($src_nodename,@src_attribs)=split(',',$ARGV[0]);

my $inmrml  = $ARGV[1];
my $outmrml  = $ARGV[2];
my $mrml_dupe;
if ( ! defined $inmrml ) { 
    print("ERROR: no mrml specified");
    exit;
}

if ( $#src_attribs<0 ) {
    print ("ERROR: did not split attributes properly: < ".$ARGV[0].">\n");
    exit;
}

my ($n,$p,$e)=fileparts($inmrml);
$mrml_dupe=$p.$n."_dup".$e;
if ( ! defined $outmrml) { 
    $outmrml=$p.$n."_mhn".$e;
    print("Auto mrml out will be \"$outmrml\".\n");
}
my ($xml_data,$xml_parser)=xml_read($inmrml,'giveparser');

if($debug_val>50){
#    dump($xml_parser);
#    dump($xml_data);
}
mrml_to_file($xml_data,'  ',0,'pretty','',$mrml_dupe);

my @src_nodes=mrml_find_by_name($xml_data,"^".$src_nodename."\$");# this can find many mrml nodes, but in this code we only expect 1.
#my @src_nodes=mrml_find_by_name($xml_data,"^".$src_nodename);
#dump(@src_nodes);

print("Found ".($#src_nodes+1)." nodes with matching pattern $src_nodename\n");
for(my $ri=1;$ri<=$#src_nodes;$ri++){
    my $n1=$src_nodes[($ri-1)];
    my $n2=$src_nodes[$ri];
#    print "compare $ri ".ref($src_nodes[$ri])." $src_nodes[$ri] and ".($ri-1)." ".ref($src_nodes[$ri-1])." ".$src_nodes[($ri-1)]."\n";
#    print($src_nodes[$ri]->{"name"}."\n");
#    print($src_nodes[($ri-1)]->{"name"}."\n");
    if ( mrml_node_diff($n1,$n2) ) { 
	#warn("more nodes found than expected!($#src_nodes)".join(@src_nodes,' ')."\n");
	error_out("more nodes found than expected!($#src_nodes)\n".join("\n",@src_nodes)."\n");
    }   
}
if ( $#src_nodes<0 )
{
    print("ERROR: didnt find desired node\n");
    exit;
}



#my $mrml_att_ref=mrml_find_attrs($src_nodes[1],("ref","diplayNodeRef"));
#dump($mrml_att_ref);

#get references:
#dump(@src_nodes);
###
# get referenced nodes of our target for processing.
###
my $mrmltype_mrmlids={};
if ( 1 ) { 
# make a hash{mrmlid}=ref 
#while a array_of_refs=getref call gets refs, 
# get refs foreach ref?
#$mrmltype_mrmlids=mrml_get_refs($src_nodes[1]);
    dump(@src_nodes);
    $mrmltype_mrmlids=mrml_get_refs($xml_data,$src_nodes[0]);
# get refs makes a hash{mrmltype}=@arrayofids. 
} else {
    my %nodelinks;
    my %nodes_by_mrmltype;
    my @all_nodes;
    for my $node ( @src_nodes) {
	my $references=$node->{"references"};
	my @refs = $references =~ /([[:alnum:]]+[:])([[:alnum:]]+)([\s]+[[:alnum:]]+)?/xg;
	#dump(@refs);
	my $node_reftype='';
	foreach my $rn (@refs){
	    if ( defined $rn ) {
		if (my(@vars)=$rn =~ /[\s]*([[:alnum:]]+)[:]/) {
		    $node_reftype=$1;
		    #dump(@vars);
		} else { #we're a node id lets find the mmrl node typel
		    $rn =~ s/[\s:]//gx;
		    my ($mrml_type) = $rn =~ /vtkMRML(.*?)(?:Node)?/x;
		    
		    if ( ! defined $nodelinks{$node_reftype}) {# clever way to build hierarchy hash on fly. 
			$nodelinks{$node_reftype}=(); 
		    }
		    if ( ! defined $nodes_by_mrmltype{$mrml_type}) {# clever way to build hierarchy hash on fly. 
			$nodes_by_mrmltype{$mrml_type}=();
			print("Adding mrml_type $mrml_type");
		    }
		    push(@{$nodelinks{$node_reftype}},$rn);
		    push(@{$nodes_by_mrmltype{$mrml_type}},$rn);
		    push(@all_nodes,$rn);
		}
	    }
	}
	#mrml_find_by_id();
    }

# sort nodes in order : ) 
    foreach my $node_reftype (keys(%nodelinks)){
	@{$nodelinks{$node_reftype}} = sort( @{$nodelinks{$node_reftype}} );
    }

    print("Node types in refs\n");
    dump(%nodelinks);
    print("Mrml types in refs\n");
    dump(%nodes_by_mrmltype);

#my ($mrml_type) = $rn =~ /vtkMRML(.*?)Node/x;
    foreach my $mrml_type (keys(%nodes_by_mrmltype) ){
	print("TYPE$mrml_type\n");
	my @mln=@{$nodes_by_mrmltype{$mrml_type}};
	dump(@mln);
	#print("nodes ". join(@mln," "));
	#dump($nodes_by_mrmltype{$mrml_type});
	if ($#mln==1) {
	    my ($n1)=mrml_find_by_id($xml_data,"^".$mln[0]."\$");
	    my ($n2)=mrml_find_by_id($xml_data,"^".$mln[1]."\$");
	    if ( !mrml_node_diff($n1,$n2 ) ){
		dump($n1);
		#print("no_diff for nodes\n"); 
	    }
	}

    }

# foreach my $node_reftype (keys(%nodelinks)){
#     print("$node_reftype\n");
#     foreach my $nodeid (@{$nodelinks{$node_reftype}}) {
# 	print("$nodeid\n");
# 	push(@nodes_of_type, mrml_find_by_id($xml_data,"^".$nodeid."\$"));
#     }
# }

#if ( mrml_node_diff($src_nodes[$ri],$src_nodes[$ri+1]) ) { 
#$node->{"name"}="v1_${value}_$alt_name";
}
#####vtkMRMLDiffusionTensorDisplayPropertiesNode1!
dump($mrmltype_mrmlids);
#foreach key, get key from primary node, apply to sub nodes, if key not in primary node, try the references, check references by type. 

#get src_node type.
#my @dest_noodes=
#my @src_nodes=mrml_find_by_name($xml_data,"^".$src_node);

# more than one source node at this point is an error! so we dont need to handle multiple sources.


my $src_node=$src_nodes[0]; #my ($src_node)=@src_nodes; #just the first element?
#my ($mrml_type) = $src_node->{"id"} =~ /vtkMRML(.*?)Node/x;
#my @dest_nodes=mrml_find_by_id($xml_data,$mrml_type,$mrml_type);
##mrml_attr_search($mrml_tree,$attr,$value,$type);

dump(mrml_types($xml_data));# dump the mrml types in use in this scene.

my %attr_val=();
# process each desired attribute
for my $src_attr ( @src_attribs) { 
    print("Copying from ". $src_node->{"id"}."\n");
    my ($mrml_type,@junk) = $src_node->{"id"} =~ /vtkMRML(.*?)(?:Node)?(?:[0-9]+)$/x;
    if ( defined $src_node->{$src_attr} ) { 
	if (defined $attr_val{$src_attr} && $src_node->{$src_attr} ne $attr_val{$src_attr}) { 
	    warn(" $src_attr value change between nodes.".$attr_val{$src_attr}." changing to ".$src_node->{$src_attr}."\n");
	}
	$attr_val{$src_attr}=$src_node->{$src_attr};
	my @dest_nodes =();
	if ( 1 ) { 
	    #@dest_nodes=mrml_find_by_id($xml_data,$mrml_type,$mrml_type);
	    @dest_nodes=mrml_find_by_type($xml_data,$mrml_type);
	} else {
	    
	    if ( defined $xml_data->{"MRML"}->{$mrml_type}) {
		@dest_nodes=@{$xml_data->{"MRML"}->{$mrml_type}};
	    } else { 
	    }
	}
	print("$src_attr, found ".($#dest_nodes+1)." nodes of type $mrml_type to update ...");
	foreach (@dest_nodes){
	    $_->{$src_attr}=$src_node->{$src_attr};
	}
	print(" Update done.\n");
    } else {
	print("$src_attr, missing in primary node, trying sub nodes.\n");
	#dump($src_node);
	for my $sub_mrml_type ( keys(%{$mrmltype_mrmlids}) ){ 
	    print("\tlooking up nodetype $sub_mrml_type\n");
	    my @mrml_ids=@{$mrmltype_mrmlids->{$sub_mrml_type}};
	    #dump(@mrml_ids);
	    for my $src_id (@mrml_ids){
		print("\t\t$src_id\n");
		#my $src_id=$mrml_ids[0]; #my ($mrml_id)=@mrml_ids; #just the first element?
		my @alt_src_nodes=mrml_find_by_id($xml_data,$src_id."\$");
		if ($#alt_src_nodes>0 ) { 
		print("Found ".($#alt_src_nodes+1)." nodes with matching pattern $src_nodename\n");

		for(my $ri=1;$ri<=$#alt_src_nodes;$ri++){
		    my $n1=$alt_src_nodes[($ri-1)];
		    my $n2=$alt_src_nodes[$ri];
		    if ( mrml_node_diff($n1,$n2) ) { 
			#warn("more nodes found than expected!($#src_nodes)".join(@src_nodes,' ')."\n");
			dump(@alt_src_nodes);
			exit("more nodes found than expected!($#alt_src_nodes)".join(@alt_src_nodes,' ')."\n");
		    }   
		}
		}
		my $alt_src_node=$alt_src_nodes[0]; #my ($src_node)=@src_nodes; #just the first element?
		if ( $#alt_src_nodes>0) {
		    warn("more than one match per source node\n");
		}
		#dump($alt_src_node);
		if ( defined $alt_src_node->{"id"} ) {
		    if ( defined $alt_src_node->{$src_attr}) { 
		    if (defined $attr_val{$src_attr} && $alt_src_node->{$src_attr} ne $attr_val{$src_attr}) { 
			warn(" $src_attr value change between nodes.".$attr_val{$src_attr}." changing to ".$alt_src_node->{$src_attr}."\n");
		    }
		    $attr_val{$src_attr}=$alt_src_node->{$src_attr};
		    #dump(@mrml_ids);
		    my @dest_nodes=mrml_find_by_id($xml_data,$sub_mrml_type);#,$sub_mrml_type);
		    print("\t\t$src_attr, found ".($#dest_nodes+1)." nodes to update ...");
		    foreach (@dest_nodes){
			#print("\t\t\t".$_->{"id"}." ".$alt_src_node->{$src_attr}." =/= ".$_->{$src_attr});
			$_->{$src_attr}=$alt_src_node->{$src_attr};
			#print("->".$_->{$src_attr}."\n");
		    }
		    print(" Update done.\n");
		} else { 
		    print("\t\t\t$src_attr unavailable for ".$alt_src_node->{"id"}.".\n");
		    #dump($alt_src_node);
		} } else {
		    print("\t\t\t$src_id unavailable.\n");
		}
	    }
	}
    }
}






###
# verify we're modifing
###
##mrml_attr_search($mrml_tree,$attr,$value,$type);
for my $src_attr ( @src_attribs ) {
    print("Verifing $src_attr\n");
    #my @found_nodes=mrml_attr_search($xml_data,$src_attr,".*","FiberBundleLineDisplayNode");
    #my @found_modified_nodes=mrml_attr_search($xml_data,$src_attr,$attr_val{$src_attr},"FiberBundleLineDisplayNode");
    my @found_nodes=mrml_attr_search($xml_data,$src_attr,".*");
    my @found_modified_nodes=mrml_attr_search($xml_data,$src_attr,$attr_val{$src_attr});
    print("\tmodified ". ($#found_modified_nodes+1)." of ". ( $#found_nodes+1 ) . "possible nodes\n");
}
#$attr_val{$src_attr}
#dump(@found_modified_nodes);




mrml_to_file($xml_data,'  ',0,'pretty','',$outmrml);
exit();

#get LineDisplayNode
#vtkMRMLFiberBundleLineDisplayNode2

my $node=$src_nodes[0];
#display_complex_data_structure($node);
my $node_id=$node->{'id'};
if ( defined $node_id  ) {
    my @mrmls_found=mrml_attr_search($xml_data,"associatedNodeRef",$node_id."\$","ModelHierarchy");
    #print("found ".($#mrmls_found+1)." references to this node\n");
    foreach my $mrml_node ( @mrmls_found){
	#print("change node $mrml_node->{id} $mrml_node->{name} to $alt_name\n");
	#$mrml_node->{"name"}="v1_${value}_$alt_name";
	#$node->{"name"}="v1_${value}_$alt_name";
    }
    
}

#if( $rename_type eq 'modelfile' || $rename_type eq 'ontology' || $rename_type eq 'abrev') {
#    mrml_clear_nodes($xml_data,("ModelHierarchy","ModelDisplay","Version", "UserTags"));
#    mrml_to_file($xml_data,'  ',0,'pretty','',$outmrml);
#    write_array_to_file($color_table_out,\@color_table);
#}#$rename_type eq 'clean' ||
