#!/bin/bash

#
#-----------------------------------------------------------------------
#
# Source the variable definitions file and the bash utility functions.
#
#-----------------------------------------------------------------------
#
. ${GLOBAL_VAR_DEFNS_FP}
. $USHdir/source_util_funcs.sh
#
#-----------------------------------------------------------------------
#
# Save current shell options (in a global array).  Then set new options
# for this script/function.
#
#-----------------------------------------------------------------------
#
{ save_shell_opts; set -u -x; } > /dev/null 2>&1
#
#-----------------------------------------------------------------------
#
# Get the full path to the file in which this script/function is located 
# (scrfunc_fp), the name of that file (scrfunc_fn), and the directory in
# which the file is located (scrfunc_dir).
#
#-----------------------------------------------------------------------
#
scrfunc_fp=$( readlink -f "${BASH_SOURCE[0]}" )
scrfunc_fn=$( basename "${scrfunc_fp}" )
scrfunc_dir=$( dirname "${scrfunc_fp}" )
#
#-----------------------------------------------------------------------
#
# Print message indicating entry into script.
#
#-----------------------------------------------------------------------
#
print_info_msg "
========================================================================
Entering script:  \"${scrfunc_fn}\"
In directory:     \"${scrfunc_dir}\"

This is the ex-script for the task that runs the post-processor (UPP) on
the output files corresponding to a specified forecast hour.
========================================================================"
#
#-----------------------------------------------------------------------
#
# Specify the set of valid argument names for this script/function.  
# Then process the arguments provided to this script/function (which 
# should consist of a set of name-value pairs of the form arg1="value1",
# etc).
#
#-----------------------------------------------------------------------
#
valid_args=( \
"cdate" \
"run_dir" \
"postprd_dir" \
"comout" \
"fhr_dir" \
"fhr" \
"tmmark" \
)
process_args valid_args "$@"
#
#-----------------------------------------------------------------------
#
# For debugging purposes, print out values of arguments passed to this
# script.  Note that these will be printed out only if VERBOSE is set to
# TRUE.
#
#-----------------------------------------------------------------------
#
print_input_args valid_args
#
#-----------------------------------------------------------------------
#
# Load modules.
#
#-----------------------------------------------------------------------
#
case $MACHINE in

  "WCOSS2")
    ulimit -s unlimited
    ulimit -a
    export OMP_NUM_THREADS=1
    ncores=$(( NNODES_RUN_PRDGEN*PPN_RUN_PRDGEN))
    APRUN="mpiexec -n ${ncores} -ppn ${PPN_RUN_PRDGEN}"
    ;;

  "HERA")
    APRUN="srun"
    ;;

  "ORION")
    ulimit -s unlimited
    ulimit -a
    export OMP_NUM_THREADS=1
    export OMP_STACKSIZE=1024M
    APRUN="srun"
    ;;

  "JET")
    APRUN="srun"
    ;;

  "ODIN")
    APRUN="srun -n 1"
    ;;

  "CHEYENNE")
    module list
    nprocs=$(( NNODES_RUN_POST*PPN_RUN_POST ))
    APRUN="mpirun -np $nprocs"
    ;;

  "STAMPEDE")
    nprocs=$(( NNODES_RUN_POST*PPN_RUN_POST ))
    APRUN="ibrun -n $nprocs"
    ;;

  *)
    print_err_msg_exit "\
Run command has not been specified for this machine:
  MACHINE = \"$MACHINE\"
  APRUN = \"$APRUN\""
    ;;

esac
#
#-----------------------------------------------------------------------
#
# Get the cycle date and hour (in formats of yyyymmdd and hh, respectively)
# from cdate.
#
#-----------------------------------------------------------------------
#
yyyymmdd=${cdate:0:8}
hh=${cdate:8:2}
cyc=$hh
#-----------------------------------------------------------------------
#
# A separate ${post_fhr} forecast hour variable is required for the post
# files, since they may or may not be three digits long, depending on the
# length of the forecast.
#
#-----------------------------------------------------------------------
#

len_fhr=${#fhr}
if [ ${len_fhr} -eq 9 ]; then
  post_min=${fhr:4:2}
  if [ ${post_min} -lt 15 ]; then
    post_min=00
  fi
else
  post_min=00
fi

subh_fhr=${fhr}
if [ ${len_fhr} -eq 2 ]; then
  post_fhr=${fhr}00
elif [ ${len_fhr} -eq 3 ]; then
  if [ "${fhr:0:1}" = "0" ]; then
    post_fhr="${fhr:1}00"
  else
    post_fhr=${fhr}00
  fi
elif [ ${len_fhr} -eq 9 ]; then
  if [ "${fhr:0:1}" = "0" ]; then
    if [ ${post_min} -eq 00 ]; then
      post_fhr="${fhr:1:2}00"
      subh_fhr="${fhr:0:3}"
    else
      post_fhr="${fhr:1:2}${fhr:4:2}"
    fi
  else
    if [ ${post_min} -eq 00 ]; then
      post_fhr="${fhr:0:3}00"
      subh_fhr="${fhr:0:3}"
    else
      post_fhr="${fhr:0:3}${fhr:4:2}"
    fi
  fi
else
  print_err_msg_exit "\
The \${fhr} variable contains too few or too many characters:
  fhr = \"$fhr\""
fi

# replace fhr with subh_fhr
echo "fhr=${fhr} and subh_fhr=${subh_fhr}"
fhr=${subh_fhr}
#
gridname=""
if [ ${PREDEF_GRID_NAME} = "RRFS_CONUS_3km" ]; then
  gridname="conus_3km."
elif  [ ${PREDEF_GRID_NAME} = "RRFS_NA_3km" ]; then
  gridname=""
fi
#
net4=$(echo ${NET:0:4} | tr '[:upper:]' '[:lower:]')
#
bgdawp=${postprd_dir}/${NET}.t${cyc}z.bgdawpf${fhr}.${tmmark}.grib2
bgrd3d=${postprd_dir}/${NET}.t${cyc}z.bgrd3df${fhr}.${tmmark}.grib2
bgifi=${postprd_dir}/${NET}.t${cyc}z.bgifif${fhr}.${tmmark}.grib2
bgsfc=${postprd_dir}/${NET}.t${cyc}z.bgsfcf${fhr}.${tmmark}.grib2

prslev=${net4}.t${cyc}z.prslev.f${fhr}.${gridname}grib2
natlev=${net4}.t${cyc}z.natlev.f${fhr}.${gridname}grib2
ififip=${net4}.t${cyc}z.ififip.f${fhr}.${gridname}grib2
testbed=${net4}.t${cyc}z.testbed.f${fhr}.${gridname}grib2

# extract the output fields for the testbed
touch ${bgsfc}
if [[ ! -z ${TESTBED_FIELDS_FN} ]]; then
  if [[ -f ${FIX_UPP}/${TESTBED_FIELDS_FN} ]]; then
    wgrib2 ${postprd_dir}/${prslev} | grep -F -f ${FIX_UPP}/${TESTBED_FIELDS_FN} | wgrib2 -i -grib ${postprd_dir}/${testbed} ${postprd_dir}/${prslev}
  else
    echo "${FIX_UPP}/${TESTBED_FIELDS_FN} not found"
  fi
fi
if [[ ! -z ${TESTBED_FIELDS_FN2} ]]; then
  if [[ -f ${FIX_UPP}/${TESTBED_FIELDS_FN2} ]]; then
    wgrib2 ${postprd_dir}/${natlev} | grep -F -f ${FIX_UPP}/${TESTBED_FIELDS_FN2} | wgrib2 -i -append -grib ${postprd_dir}/${testbed} ${postprd_dir}/${natlev}
  else
    echo "${FIX_UPP}/${TESTBED_FIELDS_FN2} not found"
  fi
fi

#Link output for transfer to Jet
# Should the following be done only if on jet??

# Seems like start_date is the same as "$yyyymmdd $hh", where yyyymmdd
# and hh are calculated above, i.e. start_date is just cdate but with a
# space inserted between the dd and hh.  If so, just use "$yyyymmdd $hh"
# instead of calling sed.

basetime=$( date +%y%j%H%M -d "${yyyymmdd} ${hh}" )
cp_vrfy ${postprd_dir}/${prslev} ${comout}/${prslev}
cp_vrfy ${postprd_dir}/${natlev} ${comout}/${natlev}
if [ -f  ${postprd_dir}/${ififip} ]; then
  cp_vrfy ${postprd_dir}/${ififip} ${comout}/${ififip}
fi
cp_vrfy ${postprd_dir}/${testbed}  ${comout}/${testbed}
ln_vrfy -sf --relative ${comout}/${prslev} ${comout}/BGDAWP_${basetime}${post_fhr}
ln_vrfy -sf --relative ${comout}/${natlev} ${comout}/BGRD3D_${basetime}${post_fhr}
if [ -f ${comout}/${ififip} ]; then
  ln_vrfy -sf --relative ${comout}/${ififip} ${comout}/BGIFI_${basetime}${post_fhr}
fi
ln_vrfy -sf --relative ${comout}/${testbed}  ${comout}/BGSFC_${basetime}${post_fhr}

ln_vrfy -sf --relative ${comout}/${prslev} ${comout}/${NET}.t${cyc}z.bgdawpf${fhr}.${tmmark}.grib2
wgrib2 ${comout}/${prslev} -s > ${comout}/${prslev}.idx
ln_vrfy -sf --relative ${comout}/${natlev} ${comout}/${NET}.t${cyc}z.bgrd3df${fhr}.${tmmark}.grib2
wgrib2 ${comout}/${natlev} -s > ${comout}/${natlev}.idx
if [ -f ${comout}/${ififip} ]; then
  ln_vrfy -sf --relative ${comout}/${ififip} ${comout}/${NET}.t${cyc}z.bgifif${fhr}.${tmmark}.grib2
  wgrib2 ${comout}/${ififip} -s > ${comout}/${ififip}.idx
fi
ln_vrfy -sf --relative ${comout}/${testbed} ${comout}/${NET}.t${cyc}z.bgsfcf${fhr}.${tmmark}.grib2
wgrib2 ${comout}/${testbed} -s > ${comout}/${testbed}.idx
# Remap to additional output grids if requested

if [ ${DO_PARALLEL_PRDGEN} == "TRUE" ]; then
#
#  parallel run wgrib2 for product generation
#

if [ ${PREDEF_GRID_NAME} = "RRFS_NA_3km" ]; then

module load cfp/2.0.4
DATA=$postprd_dir
export DATA=$postprd_dir
DATAprdgen=$DATA/prdgen_${fhr}
mkdir $DATAprdgen
USHrrfs=$USHdir/prdgen

wgrib2 ${comout}/rrfs.t${cyc}z.prslev.f${fhr}.grib2 >& $DATAprdgen/prslevf${fhr}.txt

# Create parm files for subsetting on the fly - do it for each forecast hour
# 10 subpieces for North American grid
sed -n -e '1,120p' $DATAprdgen/prslevf${fhr}.txt >& $DATAprdgen/namerica_1.txt
sed -n -e '121,240p' $DATAprdgen/prslevf${fhr}.txt >& $DATAprdgen/namerica_2.txt
sed -n -e '241,360p' $DATAprdgen/prslevf${fhr}.txt >& $DATAprdgen/namerica_3.txt
sed -n -e '361,480p' $DATAprdgen/prslevf${fhr}.txt >& $DATAprdgen/namerica_4.txt
sed -n -e '481,600p' $DATAprdgen/prslevf${fhr}.txt >& $DATAprdgen/namerica_5.txt
sed -n -e '601,720p' $DATAprdgen/prslevf${fhr}.txt >& $DATAprdgen/namerica_6.txt
sed -n -e '721,750p' $DATAprdgen/prslevf${fhr}.txt >& $DATAprdgen/namerica_7.txt
sed -n -e '751,780p' $DATAprdgen/prslevf${fhr}.txt >& $DATAprdgen/namerica_8.txt
sed -n -e '781,880p' $DATAprdgen/prslevf${fhr}.txt >& $DATAprdgen/namerica_9.txt
sed -n -e '881,$p' $DATAprdgen/prslevf${fhr}.txt >& $DATAprdgen/namerica_10.txt

# 4 subpieces for CONUS and Alaska grids
sed -n -e '1,250p' $DATAprdgen/prslevf${fhr}.txt >& $DATAprdgen/conus_ak_1.txt
sed -n -e '251,500p' $DATAprdgen/prslevf${fhr}.txt >& $DATAprdgen/conus_ak_2.txt
sed -n -e '501,750p' $DATAprdgen/prslevf${fhr}.txt >& $DATAprdgen/conus_ak_3.txt
sed -n -e '751,$p' $DATAprdgen/prslevf${fhr}.txt >& $DATAprdgen/conus_ak_4.txt

# 2 subpieces for Hawaii and Puerto Rico grids
sed -n -e '1,500p' $DATAprdgen/prslevf${fhr}.txt >& $DATAprdgen/hi_pr_1.txt
sed -n -e '501,$p' $DATAprdgen/prslevf${fhr}.txt >& $DATAprdgen/hi_pr_2.txt

# Create script to execute production generation tasks in parallel using CFP
echo "#!/bin/bash" > $DATAprdgen/poescript_${fhr}
echo "export DATA=${DATAprdgen}" >> $DATAprdgen/poescript_${fhr}
echo "export comout=${comout}" >> $DATAprdgen/poescript_${fhr}

tasks=(4 4 2 2 10)
domains=(conus ak hi pr namerica)
count=0
for domain in ${domains[@]}
do
  for task in $(seq ${tasks[count]})
  do
    mkdir -p $DATAprdgen/prdgen_${domain}_${task}
    echo "$USHrrfs/rrfs_prdgen_subpiece.sh $fhr $cyc $task $domain ${DATAprdgen} ${comout} &" >> $DATAprdgen/poescript_${fhr}
  done
  count=$count+1
done

echo "wait" >> $DATAprdgen/poescript_${fhr}
chmod 775 $DATAprdgen/poescript_${fhr}

#
# Execute the script
#

export CMDFILE=$DATAprdgen/poescript_${fhr}
mpiexec -np 22 --cpu-bind core cfp $CMDFILE
#export err=$?; err_chk

# reassemble the output grids

tasks=(4 4 2 2 10)
domains=(conus ak hi pr namerica)
count=0
for domain in ${domains[@]}
do
  for task in $(seq ${tasks[count]})
  do
    cat $DATAprdgen/prdgen_${domain}_${task}/${domain}_${task}.grib2 >> ${comout}/rrfs.t${cyc}z.prslev.f${fhr}.${domain}.grib2
  done
  wgrib2 ${comout}/rrfs.t${cyc}z.prslev.f${fhr}.${domain}.grib2 -s > ${comout}/rrfs.t${cyc}z.prslev.f${fhr}.${domain}.grib2.idx
  count=$count+1
done

# Rename conus grib2 files to conus_3km
mv ${comout}/rrfs.t${cyc}z.prslev.f${fhr}.conus.grib2 ${comout}/rrfs.t${cyc}z.prslev.f${fhr}.conus_3km.grib2
mv ${comout}/rrfs.t${cyc}z.prslev.f${fhr}.conus.grib2.idx ${comout}/rrfs.t${cyc}z.prslev.f${fhr}.conus_3km.grib2.idx

else
  echo "this grid is not ready for parallel prdgen: ${PREDEF_GRID_NAME}"
fi
else
#
# use single core to process all addition grids.
#
if [ ${#ADDNL_OUTPUT_GRIDS[@]} -gt 0 ]; then

  cd_vrfy ${comout}

  grid_specs_130="lambert:265:25.000000 233.862000:451:13545.000000 16.281000:337:13545.000000"
  grid_specs_200="lambert:253:50.000000 285.720000:108:16232.000000 16.201000:94:16232.000000"
  grid_specs_221="lambert:253:50.000000 214.500000:349:32463.000000 1.000000:277:32463.000000"
  grid_specs_242="nps:225:60.000000 187.000000:553:11250.000000 30.000000:425:11250.000000"
  grid_specs_243="latlon 190.0:126:0.400 10.000:101:0.400"
  grid_specs_clue="lambert:262.5:38.5 239.891:1620:3000.0 20.971:1120:3000.0"
  grid_specs_hrrr="lambert:-97.5:38.5 -122.719528:1799:3000.0 21.138123:1059:3000.0"
  grid_specs_hrrre="lambert:-97.5:38.5 -122.719528:1800:3000.0 21.138123:1060:3000.0"
  grid_specs_rrfsak="lambert:-161.5:63.0 172.102615:1379:3000.0 45.84576:1003:3000.0"
  grid_specs_hrrrak="nps:225:60.000000 185.117126:1299:3000.0 41.612949:919:3000.0"

  for grid in ${ADDNL_OUTPUT_GRIDS[@]}
  do
    for leveltype in prslev natlev ififip testbed
    do
      
      eval grid_specs=\$grid_specs_${grid}
      subdir=${postprd_dir}/${grid}_grid
      mkdir -p ${subdir}/${fhr}
      bg_remap=${subdir}/${net4}.t${cyc}z.${leveltype}.f${fhr}.${grid}.grib2

      # Interpolate fields to new grid
      eval infile=${comout}/${net4}.t${cyc}z.${leveltype}.f${fhr}.${gridname}grib2
      if [ ${PREDEF_GRID_NAME} = "RRFS_NA_13km" ]; then
         wgrib2 ${infile} -set_bitmap 1 -set_grib_type c3 -new_grid_winds grid \
           -new_grid_vectors "UGRD:VGRD:USTM:VSTM:VUCSH:VVCSH" \
           -new_grid_interpolation bilinear \
           -if ":(WEASD|APCP|NCPCP|ACPCP|SNOD):" -new_grid_interpolation budget -fi \
           -if ":(NCONCD|NCCICE|SPNCR|CLWMR|CICE|RWMR|SNMR|GRLE|PMTF|PMTC|REFC|CSNOW|CICEP|CFRZR|CRAIN|LAND|ICEC|TMP:surface|VEG|CCOND|SFEXC|MSLMA|PRES:tropopause|LAI|HPBL|HGT:planetary boundary layer):|ICPRB|SIPD|ICSEV" -new_grid_interpolation neighbor -fi \
           -new_grid ${grid_specs} ${subdir}/${fhr}/tmp_${grid}.grib2 &
      else
         wgrib2 ${infile} -set_bitmap 1 -set_grib_type c3 -new_grid_winds grid \
           -new_grid_vectors "UGRD:VGRD:USTM:VSTM:VUCSH:VVCSH" \
           -new_grid_interpolation neighbor \
           -new_grid ${grid_specs} ${subdir}/${fhr}/tmp_${grid}.grib2 &
      fi
      wait 

      # Merge vector field records
      wgrib2 ${subdir}/${fhr}/tmp_${grid}.grib2 -new_grid_vectors "UGRD:VGRD:USTM:VSTM:VUCSH:VVCSH" -submsg_uv ${bg_remap} &
      wait 

      # Remove temporary files
      rm -f ${subdir}/${fhr}/tmp_${grid}.grib2

      # Save to com directory 
      mkdir -p ${comout}/${grid}_grid
      cp_vrfy ${bg_remap} ${comout}/${net4}.t${cyc}z.${leveltype}.f${fhr}.${grid}.grib2
      wgrib2 ${comout}/${net4}.t${cyc}z.${leveltype}.f${fhr}.${grid}.grib2 -s > ${comout}/${net4}.t${cyc}z.${leveltype}.f${fhr}.${grid}.grib2.idx

      if [ $leveltype = 'prslev' ]; then
         ln_vrfy -fs --relative ${comout}/${net4}.t${cyc}z.${leveltype}.f${fhr}.${grid}.grib2 ${comout}/${grid}_grid/${NET}.t${cyc}z.bgdawpf${fhr}.${tmmark}.grib2
         ln_vrfy -fs --relative ${comout}/${net4}.t${cyc}z.${leveltype}.f${fhr}.${grid}.grib2 ${comout}/${grid}_grid/BGDAWP_${basetime}${post_fhr}
      fi

      if [ $leveltype = 'natlev' ]; then
         ln_vrfy -fs --relative ${comout}/${net4}.t${cyc}z.${leveltype}.f${fhr}.${grid}.grib2 ${comout}/${grid}_grid/${NET}.t${cyc}z.bgrd3df${fhr}.${tmmark}.grib2
         ln_vrfy -fs --relative ${comout}/${net4}.t${cyc}z.${leveltype}.f${fhr}.${grid}.grib2 ${comout}/${grid}_grid/BGRD3D_${basetime}${post_fhr}
      fi

      if [[ $leveltype = 'ififip' ]] && [[ -f ${comout}/${net4}.t${cyc}z.${leveltype}.f${fhr}.${grid}.grib2  ]]; then
         ln_vrfy -fs --relative ${comout}/${net4}.t${cyc}z.${leveltype}.f${fhr}.${grid}.grib2 ${comout}/${grid}_grid/${NET}.t${cyc}z.bgifif${fhr}.${tmmark}.grib2
         ln_vrfy -fs --relative ${comout}/${net4}.t${cyc}z.${leveltype}.f${fhr}.${grid}.grib2 ${comout}/${grid}_grid/BGIFI_${basetime}${post_fhr}
      fi

      if [ $leveltype = 'testbed' ]; then
         ln_vrfy -fs --relative ${comout}/${net4}.t${cyc}z.${leveltype}.f${fhr}.${grid}.grib2 ${comout}/${grid}_grid/${NET}.t${cyc}z.bgsfcf${fhr}.${tmmark}.grib2
         ln_vrfy -fs --relative ${comout}/${net4}.t${cyc}z.${leveltype}.f${fhr}.${grid}.grib2 ${comout}/${grid}_grid/BGSFC_${basetime}${post_fhr}
      fi

    done
  done
fi

fi  # block for parallel or series wgrib2 runs.

rm_vrfy -rf ${fhr_dir}
#
#-----------------------------------------------------------------------
#
# Print message indicating successful completion of script.
#
#-----------------------------------------------------------------------
#
print_info_msg "
========================================================================
Post-processing for forecast hour $fhr completed successfully.

Exiting script:  \"${scrfunc_fn}\"
In directory:    \"${scrfunc_dir}\"
========================================================================"
#
#-----------------------------------------------------------------------
#
# Restore the shell options saved at the beginning of this script/func-
# tion.
#
#-----------------------------------------------------------------------
#
{ restore_shell_opts; } > /dev/null 2>&1
