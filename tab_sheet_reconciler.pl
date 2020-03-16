#!/usr/bin/env perl
# Take two tab sheets, and filter/sort information
# Wowo this is tough...
# This was written to take a simple abbrev__name, parent_path spreadsheet and get the entries from a complete sheet.
# the parent paths in the complete spreadsheets will be supersets, and have to be trimmed.
#
# So there's lots of guessing...
#
use strict;
use warnings;
use Data::Dump qw(dump);
use Clone qw(clone);
use Getopt::Std;
use File::Basename;
#use Text::Trim qw(trim);
#use List::MoreUtils qw(uniq);

my $ERROR_EXIT = 1;
my $GOOD_EXIT  = 0;
use Env qw(RADISH_PERL_LIB WKS_SETTINGS); # root of radish pipeline folders
if (! defined($RADISH_PERL_LIB)) {
    print STDERR "Cannot find good perl directories, quiting\n";
    exit $ERROR_EXIT;
}
use lib split(':',$RADISH_PERL_LIB);
use Headfile;
use pipeline_utilities;
use civm_simple_util qw(load_file_to_array write_array_to_file get_engine_constants_path printd whoami whowasi debugloc sleep_with_countdown trim uniq $debug_val $debug_locator);
use text_sheet_utils;


exit main(@ARGV);

1;

sub main { 
    my ($partial_info_path, $complete_info_path)=@_;
    my $input_column="Name in Avizo";
    my $splitter={};
    $splitter->{"Regex"}='^_?(.+?)(?:__?_?(.*))$';# taking this regex
    # Its not clear if splitter wants an array ref or what...
    # reformulate this var, keeping original in other
    # In our case, we can configure the input column thusly.
    #$splitter->{"Input"}=[qw(Structure Structure)];
    # reformulate var, keeping original in other
    # eg, ABA_abbrev_name is renamed(copied?) to Structure, and has Abbrev and Name derrived.
    #$splitter->{"Input"}=[qw(ABA_abbrev__name Structure)];
    $splitter->{"Input"}=[$input_column, "Structure"];
    $splitter->{"Output"}=[qw(Abbrev Name)];  # generating these two
    my $h_info={};
    $h_info->{"Splitter"}=$splitter;
    $h_info->{"Separator"}="	";# prefer tabs :) 
    my $p_table=text_sheet_utils::loader($partial_info_path,$h_info);
    # P_table, names are unique, but paths are not.
    #dump keys(%$p_table);die;
    #dump($p_table);die;
    # simple splitter to just copy a column.
    #$splitter->{"Regex"}='^(.*)$';# taking this regex    
    #$splitter->{"Input"}=["name", "ABA_Name"];
    #$splitter->{"Output"}=[qw( ABA_Name)];  # generating these two
    #$h_info->{"Splitter"}=$splitter;
    my $o_table=text_sheet_utils::loader($complete_info_path,$h_info);
    # It would be good to check table for conflicts, several keys should be unique. 
    # o_table, name,id,t_line should be unique
    my $l_count=scalar(keys %{$o_table->{"t_line"}});
    my $id_count=scalar(keys %{$o_table->{"id"}});
    if ( $l_count != $id_count ) {
        print("ERROR: Id wasnt unique!!!\n");
    } else {
        #printf("o_table had %i lines\n",$l_count);
    }
    #
    # Add derrived fields to o_table 
    #
    # add children to o_table, 
    # for each structure,
    for my $d_ln ( sort {$a<=>$b} keys %{$o_table->{"t_line"}} ) {
        # data line number
        # data_entry
        my $d_entry=$o_table->{"t_line"}->{$d_ln};
        # look up its parent, 
        my $par_id=$d_entry->{"parent_structure_id"};
        if(! defined $par_id || $par_id eq "" || ! exists($o_table->{"id"}->{$par_id})  ) {
            warn("IMACULATE ENTRY id:$d_entry->{id}, name:$d_entry->{name}");next;
            Data::Dump::dump($d_entry);
            die("BASTARD DETECTED");
        } else {
            # push id into an array on that parent called children_ids
            my $parent=$o_table->{"id"}->{$par_id};
            if( ! exists($parent->{"children_ids"})  ) {
                $parent->{"children_ids"}=();
            }
            push(@{$parent->{"children_ids"}},$d_entry->{"id"});
        }
    }
    
    #Data::Dump::dump(keys(%$o_table));die;
    my $out_table={};
    my $max_levels=scalar(grep {/^Level_[0-9]+$/} keys(%{$o_table->{"Header"}}));
    # partial line number
    #my $p_ln=1;
    #for($p_ln=0;$p_ln<10;$p_ln++){
        #if (exists $p_table->{"t_line"}->{$p_ln} ){
        #print("$p_ln\n");
        #}
    #}
    # for each line of p_table process in order.
    # On load t_line should be numberd 1... n so we dont really need a read back here.
    # WAIT  Yes we do, becuase sometimes a line is rejected! Also, the header line is eaten!
    my $missing_parents={};
    my $used_ancestors={};
    my $max_t_line=0;
    for my $p_ln ( sort {$a<=>$b} keys %{$p_table->{"t_line"}} ) {
        # partial line number
        my $p_entry=$p_table->{"t_line"}->{$p_ln};
        my @parent_structures=split("/",$p_entry->{"Path"});
        # filter empties
        #@parent_structures = grep { $_ ne '' } @parent_structures;
        # filter whitespace onlies
        @parent_structures = grep /\S/, @parent_structures;
        my @output_parent_structures=();
        # parent count
        my $pc=0;
        # level_hash to be added to our partial info later(after we clone our best guess, then remove bad fields).
        my $l_h={};
        # find structures in same name_path in the o_table
        # WHAT: can we use to look up the o_entries? Path is first good guess...
        # out_entry is a temp var to hold the updated parents, and the final branch of a path.
        my $out_entry={};
        for my $par ( @parent_structures ) {
            my $par_safe_name=name_clean($par);
            if ( exists ( $o_table->{"name"}->{$par} )  ){
                if (! exists($out_table->{"Name"}->{$par_safe_name} )  ) {
                    # copy parent entry
                    my $o_entry=$o_table->{"name"}->{$par};
                    $out_entry=\%{ clone($o_entry) };
                    # remove t_line so we can update it later.
                    # the effect will be to put all parent structures at the bottom of our existing table. 
                    delete($out_entry->{"t_line"});
                    # rename select fields to ABA_(FIELD)
                    $out_entry->{"ABA_name"}=$out_entry->{"name"};
                    delete($out_entry->{"name"});
                    # add Path field
                    my @par_path=();
                    foreach (split('/',$out_entry->{"name_path"})  ){
                        push(@par_path,name_clean($_));
                    }
                    $out_entry->{"Path"}=join("/",@par_path);
                    @par_path = grep /\S/, @par_path;
                    #parent_level
                    my $pl=0;
                    for($pl=0;$pl<scalar(@par_path);$pl++){
                        my $L=sprintf("Level_%i",$pl+1);
                        $out_entry->{$L}=$par_path[$pl];
                    }
                    for(;$pl<$max_levels;$pl++){
                        my $L=sprintf("Level_%i",$pl+1);
                        $out_entry->{$L}="";
                    }
                    $out_entry->{"ABA_path"}=$out_entry->{"name_path"};
                    delete($out_entry->{"name_path"});
                    # add new Name field
                    $out_entry->{"Name"}=$par_safe_name;
                    # add Structure field
                    my $abbrev=$out_entry->{"acronym"};
                    $out_entry->{"Structure"}=$abbrev.'__'.$par_safe_name;
                    $out_entry->{"Abbrev"}=$abbrev;

                    # insert copied parent into output table in ABA_name, and Name indexes.
                    $out_table->{"ABA_name"}->{$par}=$out_entry;
                    $out_table->{"Name"}->{$par_safe_name}=$out_entry;
                    #dump([$out_entry,$o_entry]);die;# prove we clonned not, not linked.
                    # show our input and output names.
                    #print("in_name:$out_entry->{ABA_name}, out_name:$out_entry->{Name}\n");
                } else {
                    $out_entry=$out_table->{"Name"}->{$par_safe_name};
                }
                push(@output_parent_structures,$par_safe_name);
                $pc++;
                $l_h->{sprintf("Level_%i",$pc)}=$par_safe_name;
            } else {
                if( exists ($missing_parents->{$par}) ) {
                    $missing_parents->{$par}++;
                } else {
                    $missing_parents->{$par}=1;
                }
            }
        }
        # check that we found all the parents, and thow warning when we didnt.
        if( $pc==scalar(@parent_structures) ){
            #print($p_ln."x".$pc."\n";)
        } else {
            print("WARNING: $p_ln only had $pc of ".scalar(@parent_structures)." expected.\n");
        }
        ####
        # errors detected(missing parents) in one or more structure.
        # will not proceede to avoid confusion. 
        # Will check the remaining structures for same type of error, 
        # and then print out the details and quit.
        ####
        if (scalar(keys(%$missing_parents))  ) {
            next;
        }
        $p_entry->{"Path"}="/".join("/",@output_parent_structures);
        # Rename out entry to parent for clarity of later code, and so we can reuse out_entry.
        my $parent_entry=\%{ clone($out_entry) };
        #print("The parent of $p_entry->{Name}, is $parent_entry->{Name}\n");
        $out_entry={};
        # now parent_entry is our parent branch, lets get its children
        # first get the id's, then update that to the names. 
        my @candidate_structures=();
        if ( 1 ) {
            # since descendents isnt quite what we wanted, we preprocessed by making a children array per entry.
            my $a_r=$parent_entry->{"children_ids"};
            if ( defined $a_r ) {
                @candidate_structures=@{$a_r};
            }
        } else {
            # PROBLEM, descendents is THE WHOLE list of descendentes. Not the parents....
            my $candidate_ids=$parent_entry->{"descendents"};
            if( ! defined $candidate_ids) {
                Data::Dump::dump($parent_entry);
                die("Missing descendents");
            }
            @candidate_structures=split(',',$candidate_ids);
        }
        ### take candidate ids and find best match, or create new from the parent.
        {
            # hash_ref to hold details
            my $candidates={};
            # convert candidate_structure's from id's to the names, and add to candidates hash.
            # candidats hash will have Name(the clean name) ABA_name and id lookups. 
            # candidate number
            for(my $cn=0;$cn<=$#candidate_structures;$cn++){
                my $id=$candidate_structures[$cn];
                if ( exists($o_table->{"id"}->{$id})  ) {
                    my $o_entry=$o_table->{"id"}->{$id};
                    my $ABA_name=$o_entry->{"name"};
                    my $abbrev=$o_entry->{"acronym"};
                    my $Name=name_clean($ABA_name);
                    $candidates->{"id"}->{$id}=$o_entry;
                    $candidate_structures[$cn]=$Name;
                    $candidates->{"ABA_Name"}->{$ABA_name}=$o_entry;
                    $candidates->{"Name"}->{$Name}=$o_entry;
                    $candidates->{"Abbrev"}->{$abbrev}=$o_entry;
                    #print("---$id:$ABA_name - $Name ---\n");
                } else {
                    die("STRUCTURE ID ERROR!!! THIS SHOULD NOT HAPPEN");
                }
            }
            # take our name, clean it up,
            # remove "unfindable" bits...(eg there'll never be an _uncharted in aba land)
            # reduce our candidates to ones which we can grep with this reduced name. 
            my $clean_name=$p_entry->{"Name"} or die "ERROR Name field broken! line:$p_entry->{t_line}";
            $clean_name=~s/(_?UNCHARTED|_LEFT)//igx;
            trim($clean_name);
            $clean_name=name_clean($clean_name);
            # reduce candidate structures to just the ones which at least partially match the clean name we have.
            @candidate_structures=grep(/.*$clean_name.*/ix,
                                       @candidate_structures);
            # storing our match quality in hash so we can sort by val later.
            my $match_quality={};
            # candidate number
            for(my $cn=0;$cn<=$#candidate_structures;$cn++){
                my $Name=$candidate_structures[$cn];
                my $o_entry=$candidates->{"Name"}->{$Name};
                # evaluate quality of each remaining candidate.
                if ( $clean_name eq $Name  ) {
                    # we're done, this one is perfect.
                    $match_quality->{"$Name"}=1;
                } else { 
                    # clean_name is final result name cleaned up 
                    # to be more likly to match our end name
                    # len remainder vs len input name,
                    # ideal case is 0 remainder, which should be an exact match, but we adress that separately.
                    # short name, input_name
                    my ($s_name,$input_name);
                    if (length($Name) > length($clean_name)  ) {
                        $s_name=$clean_name;
                        $input_name=$Name;
                    } else {
                        $s_name=$Name;
                        $input_name=$clean_name;
                    }
                    my ($re_start,$re_end)= $input_name 
                        =~ /^(.*)$s_name(.*)$/igx;
                    my $remainder=$re_start.$re_end;
                    $match_quality->{"$Name"}=(length($input_name)-length($remainder))
                        / length($input_name);
                }
            }
            # sort match_quality keys by value.
            # sort examples
            #my @keys = sort { $h->{$a} <=> $h->{$b} } keys(%$h);
            #my @vals = @{$h}{@keys};
            @candidate_structures= sort {$match_quality->{$a} <=> $match_quality->{$b} } keys(%$match_quality);
            #print("checking found quality on ".join(@candidate_structures)."\n");
            # get best of the matches because it'll be first with our sorting. 
            # if no match is better than 80% we'll clone the parent

            if ( $#candidate_structures>=0 
                 && $match_quality->{$candidate_structures[0]} gt 0.8 ) {
                # its a good one, so lets clone it to out entry
                my $o_entry=$candidates->{"Name"}->{$candidate_structures[0]};
                $out_entry=\%{ clone($o_entry) };
                # rename select fields to ABA_(FIELD)
                $out_entry->{"ABA_name"}=$out_entry->{"name"};
                delete($out_entry->{"name"});
                $out_entry->{"ABA_path"}=$out_entry->{"name_path"};
                delete($out_entry->{"name_path"});
            } else {
                #print("No good candidate for $p_entry->{Name} \n");
                #Data::Dump::dump($match_quality);
                # bad matches across the board, lets just clone our parent and update fields
                $out_entry=\%{ clone($parent_entry) };
                # add the id to the id path becuase we'll be part of that group
                $out_entry->{"id_path"}=$out_entry->{"id_path"}."/".$out_entry->{"id"};
                # update parent id 
                $out_entry->{"parent_id"}=$out_entry->{"id"};
                # update name path
                #Data::Dump::dump($out_entry); die;
                #if ( exists($out_entry->{"ABA_path"}) && exists($out_entry->{"ABA_name"})  ) {
                    $out_entry->{"ABA_path"}=$out_entry->{"ABA_path"}."/".$out_entry->{"ABA_name"};
                #} else {
                #    Data::Dump::dump($out_entry);
                #    sleep 2;
                #}
                if( exists($parent_entry->{"children_ids"})
                    && $parent_entry->{"children_ids"}  ) {
                    $out_entry->{"Possible_ids"}=join(@{$parent_entry->{"children_ids"}},',');
                }
                # clear name,id,children_ids,acronym, because this is currently the parent info
                $out_entry->{"ABA_name"}="";
                $out_entry->{"id"}="";
                $out_entry->{"children_ids"}=();
                $out_entry->{"acronym"}="";
            }
            # insert and blank level information
            my @levels=grep {/^Level_[0-9]+$/} keys(%{$o_table->{"Header"}});
            if ( scalar(@levels)>$max_levels) {
                $max_levels=scalar(@levels);
            }
            #level number
            for(my $ln=1;$ln<scalar(@levels)+1;$ln++) {
                my $L=sprintf("Level_%i",$ln);
                if(! exists($l_h->{$L}) || ! defined($l_h->{$L})  ){
                    $l_h->{$L}="";
                }
                #warn ("Updating Levels ".$l_h->{$L});
                $out_entry->{$L}=$l_h->{$L};
            }
            
            # add new Name field
            foreach ( keys(%$p_entry)  ){
                if ( exists($out_entry->{$_})  ) {
                    if ( exists($out_entry->{'ABA_'.$_})  ) {
                        die "Strange condition with pre-existing copy var";
                    }
                }
                $out_entry->{$_}=$p_entry->{$_};
                $out_table->{$_}->{$out_entry->{$_}}=$out_entry;#multi up our index.
            }
            
            #$out_entry->{"Name"}=$p_entry->{"Name"};
            #$out_entry->{"Abbrev"}=$p_entry->{"Abbrev"};
            #$out_entry->{"Abbrev__Name"}=$p_entry->{"Structure"};
            #$out_table->{"Name"}->{$out_entry->{"Name"}}=$out_entry;
            #Data::Dump::dump($match_quality,$out_entry);die;
        }
        # this work to get the max line because we are operating on a sorted line list anyway.
        $max_t_line=$p_entry->{"t_line"};
        $p_ln++;
    }
    if (scalar(keys(%$missing_parents))) {
        Data::Dump::dump($missing_parents);
        die("will not process if parent structures not found, resolve issues, (likely minor capitalization/puncuation problems.");
    }
    # Verify unique
    my @used_lines=keys(%{$out_table->{"t_line"}});
    my @Structures=keys(%{$out_table->{"Structure"}});
    my @Names=keys(%{$out_table->{"Name"}});
    if (scalar(@Structures) ne scalar(@used_lines)  ){
        die "uneven count! Lost data, Structures ".scalar(@Structures)." ne lines".scalar(@used_lines);
    }

    #dump($out_table);
    dump(keys(%$p_table));
    dump($p_table->{"Header"});
    dump(keys(%$out_table));
    ###
    # create a header for our out_table, 
    ##
    # Dangerously re-using out_entry here. copying our full table header, and updating the two fields we edit.
    my $out_entry={};
    $out_entry=\%{ clone ($o_table->{"Header"}) };
    $out_entry->{"ABA_name"}=$out_entry->{"name"};
    delete($out_entry->{"name"});
    $out_entry->{"ABA_path"}=$out_entry->{"name_path"};
    delete($out_entry->{"name_path"});
    #copy the partial,  and get the count.
    $out_table->{"Header"}=\%{ clone ($p_table->{"Header"}) };
    my @out_header=keys(%{$out_table->{"Header"}});
    # header count to be added to the full header.
    my $hc=scalar(@out_header);
    foreach ( keys(%$out_entry) ) {
        $out_table->{"Header"}->{$_}=$out_entry->{$_}+$hc;
    }
    $hc=scalar(keys(%{$out_table->{"Header"}}));
    my @levels=grep {/^Level_[0-9]+$/} keys(%{$o_table->{"Header"}});
    if ( scalar(@levels)<$max_levels) {
        warn("Level Expansion Detected");
        sleep 2;
        #level number        
        for(my $ln=scalar(@levels)+1;$ln<$max_levels;$ln++) {
            my $L=sprintf("Level_%i",$ln);
            if( exists($out_table->{"Header"}->{$L})  ) {
                die "LOGICAL GLITCH";
            }
            $out_table->{"Header"}->{$L}=$hc;
            $hc++;
        }
    }
    $out_table->{"Header"}->{"Structure"}=$hc;$hc++;
    $out_table->{"Header"}->{"Abbrev"}=$hc;$hc++;
    $out_table->{"Header"}->{"Name"}=$hc;$hc++;

    if (scalar(@Structures) ne scalar(@Names)  ){
        # good... i think... becuase we need to add the missing names, so no warning :D !
        #warn("Differeent number of structures ".scalar(@Structures).", from names".scalar(@Names) .".");
    }

    ###
    # Create t_line for data.
    ###
    $out_entry={};
    #my @used_lines=keys(%{$out_table->{"t_line"}});
    foreach ( keys(%{$out_table->{"Name"}})  ) {
        $out_entry=$out_table->{"Name"}->{$_};
        if ( exists($out_entry->{"t_line"})
             && exists($out_table->{"t_line"}->{$out_entry->{"t_line"}} )  ) {
            # line good.
        } elsif ( exists($out_entry->{"t_line"})  ) {
            # has its own t_line, but for some reason its not indexed...
            die "UNINDEX GLITCH";
        } else {
            $max_t_line++;
            $out_entry->{"t_line"}=$max_t_line;
            $out_table->{"t_line"}->{$out_entry ->{"t_line"}}=$out_entry;
        }
    }
    dump($out_table->{"Header"});
    if (scalar(@Structures) ne scalar(@Names)  ){
        # good... i think... becuase we need to add the missing names, so no warning :D !
        warn("Differeent number of structures ".scalar(@Structures).", from names".scalar(@Names) .".");
    }
    # Save!
    my ($p,$n,$e)=fileparts($partial_info_path,3);
    my $out_path=File::Spec->catfile($p,$n.'_merge'.$e);
    
    text_sheet_utils::save_sheet($out_path,$out_table);
    print("Saved $out_path\n");
    return 0;
}

sub name_clean {
    my ($name)=@_;
    $name=~s/,/ the /gx;
    $name=~s/[ ]/_/gx;
    $name=~s/_+/_/gx;
    return $name;
}

1;
