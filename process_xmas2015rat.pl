#./ontology_hierarchy_creator.pl -h DataLibrariesRat/Wistar/Xmas2015Rat/NewLabelSet/hierarchy_rat_10_10_2016_cleanup_reorganizer_ready.csv -m DataLibrariesRat/Wistar/Xmas2015Rat/NewLabelSet/models_generated2_r.mrml -c DataLibrariesRat/Wistar/Xmas2015Rat/NewLabelSet/Developmental_00006912000_RBSC_labels_lookup.txt -t Name
#./mrml_key_strip.pl DataLibrariesRat/Wistar/Xmas2015Rat/NewLabelSet/models_generated2_r_Name_out.mrml 

#./ontology_hierarchy_creator.pl -h DataLibrariesRat/Wistar/Xmas2015Rat/NewLabelSet/hierarchy_rat_10_10_2016_cleanup_reorganizer_ready.csv -m DataLibrariesRat/Wistar/Xmas2015Rat/NewLabelSet/models_generated2_r.mrml -c DataLibrariesRat/Wistar/Xmas2015Rat/NewLabelSet/Developmental_00006912000_RBSC_labels_lookup.txt -t Abbrev



# NOT QUITE .... didnt i finish this for slicer ? ~/svnworkspaces/VoxPortSupport/labelstoamira.pl < DataLibrariesRat/Wistar/Xmas2015Rat/NewLabelSet/Developmental_00006912000_RBSC_labels_lookup.txt
# ~/svnworkspaces/VoxPortSupport/labelstoamira.pl < DataLibrariesRat/Wistar/Xmas2015Rat/NewLabelSet/Developmental_00006912000_RBSC_labels_lookup.txt 
# amira-to-slicer-lbl.pl
# amira-to-mbat-lbl.pl



# get level 123 hierarchy details
./ontology_hierarchy_creator.pl -h DataLibrariesRat/Wistar/Xmas2015Rat/NewLabelSet/hierarchy_rat_10_10_2016_cleanup_reorganizer_readyL123F1.csv -m DataLibrariesRat/Wistar/Xmas2015Rat/NewLabelSet/models_generated2_r.mrml -c DataLibrariesRat/Wistar/Xmas2015Rat/NewLabelSet/Developmental_00006912000_RBSC_labels_lookup.txt -o DataLibrariesRat/Wistar/Xmas2015Rat/NewLabelSet/models_generated2_r_L123F1_Structure_out.mrml  -t Structure

# get level 4 hierarchy details
./ontology_hierarchy_creator.pl -h DataLibrariesRat/Wistar/Xmas2015Rat/NewLabelSet/hierarchy_rat_10_10_2016_cleanup_reorganizer_readyF123L1.csv -m DataLibrariesRat/Wistar/Xmas2015Rat/NewLabelSet/models_generated2_r.mrml -c DataLibrariesRat/Wistar/Xmas2015Rat/NewLabelSet/Developmental_00006912000_RBSC_labels_lookup.txt -o DataLibrariesRat/Wistar/Xmas2015Rat/NewLabelSet/models_generated2_r_F123L1_Structure_out.mrml  -t Structure

exit;
# THIS ONE.
./ontology_hierarchy_creator.pl -h DataLibrariesRat/Wistar/Xmas2015Rat/NewLabelSet/hierarchy_rat_10_10_2016_cleanup_reorganizer_ready.csv -m DataLibrariesRat/Wistar/Xmas2015Rat/NewLabelSet/models_generated2_r.mrml -c DataLibrariesRat/Wistar/Xmas2015Rat/NewLabelSet/Developmental_00006912000_RBSC_labels_lookup.txt -t Structure
#exit;
~/svnworkspaces/VoxPortSupport/slicer-to-avizo.pl < ~/gitworkspaces/Slicer_DevSupportCode/DataLibrariesRat/Wistar/Xmas2015Rat/NewLabelSet/Developmental_00006912000_RBSC_labels_lookup_Structure_out.txt  > ~/gitworkspaces/Slicer_DevSupportCode/DataLibrariesRat/Wistar/Xmas2015Rat/xmas2015rat_RBSC_labels.atlas.xml
~/svnworkspaces/VoxPortSupport/amira-to-slicer-lbl.pl -xmlin ~/gitworkspaces/Slicer_DevSupportCode/DataLibrariesRat/Wistar/Xmas2015Rat/xmas2015rat_RBSC_labels.atlas.xml > ~/gitworkspaces/Slicer_DevSupportCode/DataLibrariesRat/Wistar/Xmas2015Rat/NewLabelSet/Developmental_00006912000_RBSC_labels_lookup_fromxml.txt 



