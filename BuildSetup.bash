#!/bin/bash
for bp in $(awk '/--- --- ---/{flag=1;next}flag' BuildIndex.txt );
do ck=$(echo "$bp" > tmp && cksum tmp |cut -f 1 -d ' ' );
  mv tmp b$ck;
  if [ ! -d "$bp" ]; 
  then mkdir -p "$bp";
  fi;
  if [ ! -e $ck -a -x  /d/workstation/bin/junction ];
  then /d/workstation/bin/junction "$ck" "$bp" ;
  else
  echo no junction, or already exists. 
  fi;  
done;
ls -ltr;
