#!/bin/bash
for bp in $(awk '/--- --- ---/{flag=1;next}flag' BuildIndex.txt );
do ck=$(echo "$bp" > tmp && cksum tmp |cut -f 1 -d ' ' );
  mv tmp b$ck;
  if [ ! -d "$bp" ]; 
  then mkdir -p "$bp";
  fi;
  if [ ! -e $ck ];
  then /c/bin/junction "$ck" "$bp" ;
  fi;  
done;
ls -ltr;
