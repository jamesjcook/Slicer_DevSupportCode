#!/usr/bin/perl
# small perl script to read an avizo am file until the line "# Data Section follows"

use strict;
use warnings;

# open
my $inpath=$ARGV[0];
my $outpath="Slicer_LUT_$ARGV[1].txt";
my $float_rx="[-]?[0-9]+(?:[.][0-9]+)?";
my $opacity=1;


open my $file_h, '<', $inpath;
warn("THIS CODE HAS NOT BEEN TESTED CORRECT, DO NOT TRY TO USE IN PRODUCTION\n");
if ($file_h != -1) 
{ 
    open my $out_file_h, '>', $outpath or die "Could not open output $outpath, did you forget to specify?"; 
#  #
    print $out_file_h "#\n";
#  #Begin table data:
    print $out_file_h "#Begin table data:\n";
#  0 background 0 0 0 0
#    print $out_file_h "0 background 0 0 0 0\n"
    my @header_l=();
    my @label_text=();
    my @section_names=();
    my $line='';
    my $section='';
    my $material='';
    # pixval is read from the Id of the label in the segmentation editor. Duplicate Id's have been seen. This indicates pixval might not be accurate. SO previous was going to be an attempt at fixing that possible issue. IT IS NOT DONE!.
    #  Explaination per JeffB (ages ago) There's a "value" attribute which one might assume represents voxel index values, but one would would be cruelly deceived.
    my $pixval=0;
    #my $pixval_prev=-1; 
    my @color=(0,0,0);
    my $materials_flag=0;
    while ( $line !~ /^(# Data section follows).*$/ ) {
	$line = <$file_h>;
	#foreach my $line (@all_lines) { 
	#if ($line =~ /^num_procs/) {  # say important line starts with "num_procs" ( it does) 
	#parameters {
	#  materials {
	#    materialname {
	#      Id pixval,
	#      Color R G B
	#    }
	#  } 
	#}
	my $indent='';
	if ( $line =~ /\s*(\w+)(\s\{)/ ) {
	    $section=$1;
	    push @section_names,$section;
	    for (my $i=0;$i<$#section_names;$i++) {
		$indent="\t".$indent;
	    }
	    if ($section eq 'Materials' || $materials_flag) {
		$materials_flag=1;
		print ( "$indent$section\n");
	    }

	} elsif ( $line =~ /\s*\}/ ) {
	    if ( $section_names[$#section_names] eq 'Materials' )
	    {
		for (my $i=0;$i<$#section_names;$i++) {
		    $indent="\t".$indent;
		}
		print($indent."END Materials\n");
		$materials_flag=0;
	    }
	    pop @section_names;
	} elsif ($line =~ /\s*Id\s([0-9]+),/ ) {
	    $pixval=$1;
	    #print("pixval=$pixval\n");
	} elsif ($line =~ /\s*Color\s($float_rx)\s($float_rx)\s($float_rx)[\s,]/ ) {
	    $color[0]=int(($1*255)+0.5);
	    $color[1]=int(($2*255)+0.5);
	    $color[2]=int(($3*255)+0.5);
	    my $o=int(($opacity*255)+0.5);
	    #if ( $section eq 'Exterior') {
	    if ( $pixval == 0) {
		$o=0;
	    }
	    my $out_line=$pixval.' '.$section.' '.$color[0].' '.$color[1].' '.$color[2]." ".$o."\n";
	    #print  $out_file_h $out_line;  # write out every line modified or not
	    #print $out_line;  # write out every line modified or not 
	}
	if ( $materials_flag ){
	    #print ( "$indent$section\n");
	    #print  $out_file_h $line;  # write out every line modified or not 
	}

    } 
    
# #EOF
    print $out_file_h "#EOF\n";
    close $out_file_h; 
    
    
    #@all_lines = <SESAME>; 
    close $file_h;
    
    
} else { 
    print STDERR "Unable to open file to read\n"; 
    return (0); 
} 

