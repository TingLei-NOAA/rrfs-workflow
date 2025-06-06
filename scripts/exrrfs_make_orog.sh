#!/bin/bash

#
#-----------------------------------------------------------------------
#
# Source the variable definitions file and the bash utility functions.
#
#-----------------------------------------------------------------------
#
. ${GLOBAL_VAR_DEFNS_FP}
. $USHrrfs/source_util_funcs.sh
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

This is the ex-script for the task that generates orography files.
========================================================================"
#
#-----------------------------------------------------------------------
#
# OpenMP environment settings.
# The orography code is optimized for 6 threads.
#
#-----------------------------------------------------------------------
#
export OMP_NUM_THREADS=6
export OMP_STACKSIZE=2048m
#
#-----------------------------------------------------------------------
#
# Load modules and set various computational parameters and directories.
#
# Note: 
# These module loads should all be moved to modulefiles.  This has been
# done for Hera but must still be done for other machines.
#
#-----------------------------------------------------------------------
#
ulimit -a
APRUN="time"
#
#-----------------------------------------------------------------------
#
# Preparatory steps before calling raw orography generation code.
#
#-----------------------------------------------------------------------
#
#-----------------------------------------------------------------------
#
# For the fire weather grid, read in the center lat/lon from the
# operational NAM fire weather nest.  The center lat/lon is set by the
# SDM.  When RRFS is implemented, a similar file will be needed.
# Rewrite the default center lat/lon values in var_defns.sh, if needed.
#
#-----------------------------------------------------------------------
#
if [ ${WGF} = "firewx" ]; then
  hh="${CDATE:8:2}"
  firewx_loc="${COMINnam}/input/nam_firewx_loc"
  center_lat=${LAT_CTR}
  center_lon=${LON_CTR}
  LAT_CTR=`grep ${hh}z $firewx_loc | awk '{print $2}'`
  LON_CTR=`grep ${hh}z $firewx_loc | awk '{print $3}'`

  if [ ${center_lat} != ${LAT_CTR} ] || [ ${center_lon} != ${LON_CTR} ]; then
    sed -i -e "s/${center_lat}/${LAT_CTR}/g" ${GLOBAL_VAR_DEFNS_FP}
    sed -i -e "s/${center_lon}/${LON_CTR}/g" ${GLOBAL_VAR_DEFNS_FP}
    . ${GLOBAL_VAR_DEFNS_FP}
  fi
fi
#
#-----------------------------------------------------------------------
#
# Copy topography and related data files from the system directory (TOPO_DIR)
# to the temporary directory.
#
#-----------------------------------------------------------------------
#
cd ${DATA}/raw_topo/tmp

cpreq -p ${TOPO_DIR}/thirty.second.antarctic.new.bin fort.15
cpreq -p ${TOPO_DIR}/landcover30.fixed .
cpreq -p ${TOPO_DIR}/gmted2010.30sec.int fort.235
#
#-----------------------------------------------------------------------
#
# The orography filtering code reads in from the grid mosaic file the
# the number of tiles, the name of the grid file for each tile, and the
# dimensions (nx and ny) of each tile.  Next, set the name of the grid
# mosaic file and create a symlink to it in filter_dir.
#
# Note that in the namelist file for the orography filtering code (created
# later below), the mosaic file name is saved in a variable called
# "grid_file".  It would have been better to call this "mosaic_file"
# instead so it doesn't get confused with the grid file for a given tile...
#
#-----------------------------------------------------------------------
#
# Set the maximum value of halos in COMOUT
mosaic_fn="${CRES}${DOT_OR_USCORE}mosaic.halo${NHW}.nc"
mosaic_fp="${COMOUT}/fix/${mosaic_fn}"

grid_fn=$( get_charvar_from_netcdf "${mosaic_fp}" "gridfiles" )
grid_fp="${COMOUT}/fix/${grid_fn}"
#
#-----------------------------------------------------------------------
#
# Set input parameters for the orography generation executable and write
# them to a text file.
#
# Note that it doesn't matter what lonb and latb are set to below because
# if we specify an input grid file to the executable read in (which is
# what we do below), then if lonb and latb are not set to the dimensions
# of the grid specified in that file (divided by 2 since the grid file
# specifies a "supergrid"), then lonb and latb effectively get reset to
# the dimensions specified in the grid file.
#
#-----------------------------------------------------------------------
#
mtnres=1
lonb=0
latb=0
jcap=0
NR=0
NF1=0
NF2=0
efac=0
blat=0

input_redirect_fn="INPS"
orogfile="none"

echo $mtnres $lonb $latb $jcap $NR $NF1 $NF2 $efac $blat > "${input_redirect_fn}"
#
# The following two inputs are read in as strings, so they must be quoted
# in the input file.
#
echo "\"${grid_fp}\"" >> "${input_redirect_fn}"
echo "\"$orogfile\"" >> "${input_redirect_fn}"
echo ".false." >> "${input_redirect_fn}"
echo "none" >> "${input_redirect_fn}"
cat "${input_redirect_fn}"
#
#-----------------------------------------------------------------------
#
# The following will create an orography file named
#
#   oro.${CRES}.tile7.nc
#
# and will place it in COMOUT.  Note that this file will include
# orography for a wide NHW cells around tile 7 (regional domain).
#
#-----------------------------------------------------------------------
#
print_info_msg "Starting orography file generation..."

export pgm="orog"
. prep_step

$APRUN ${EXECrrfs}/$pgm < "${input_redirect_fn}" >>$pgmout 2>${DATA}/raw_topo/tmp/errfile
export err=$?; err_chk
mv ${DATA}/raw_topo/tmp/errfile ${DATA}/raw_topo/tmp/errfile_orog

cd ${DATA}
#
#-----------------------------------------------------------------------
#
# Move the raw orography file from the temporary directory to raw_topo.
# In the process, rename it such that its name includes CRES and the halo
# width.
#
#-----------------------------------------------------------------------
#
raw_orog_fp_orig="${DATA}/raw_topo/tmp/out.oro.nc"
raw_orog_fn_prefix="${CRES}${DOT_OR_USCORE}raw_orog"
fn_suffix_with_halo="tile${TILE_RGNL}.halo${NHW}.nc"
raw_orog_fn="${raw_orog_fn_prefix}.${fn_suffix_with_halo}"
raw_orog_fp="${DATA}/raw_topo/${raw_orog_fn}"
mv "${raw_orog_fp_orig}" "${raw_orog_fp}"
#
#-----------------------------------------------------------------------
#
# Call the code to generate the two orography statistics files (large-
# and small-scale) needed for the drag suite.
#
#-----------------------------------------------------------------------
#
suites=( "FV3_RAP" "FV3_HRRR" "FV3_HRRR_gf" "FV3_GFS_v15_thompson_mynn_lam3km" "FV3_GFS_v17_p8" )
if [[ ${suites[@]} =~ "${CCPP_PHYS_SUITE}" ]] ; then
  cd ${DATA}/temp_orog_data
  mosaic_fn_gwd="${CRES}${DOT_OR_USCORE}mosaic.halo${NH4}.nc"
  mosaic_fp_gwd="${COMOUT}/fix/${mosaic_fn_gwd}"
  grid_fn_gwd=$( get_charvar_from_netcdf "${mosaic_fp_gwd}" "gridfiles" )
  export err=$?
  if [ $err -ne 0 ]; then
    err_exit "get_charvar_from_netcdf function failed."
  fi
  grid_fp_gwd="${COMOUT}/fix/${grid_fn_gwd}"
  ls_fn="geo_em.d01.lat-lon.2.5m.HGT_M.nc"
  ss_fn="HGT.Beljaars_filtered.lat-lon.30s_res.nc"
  create_symlink_to_file target="${grid_fp_gwd}" symlink="${DATA}/temp_orog_data/${grid_fn_gwd}" relative="FALSE"
  create_symlink_to_file target="${FIXam}/${ls_fn}" symlink="${DATA}/temp_orog_data/${ls_fn}" relative="FALSE"
  create_symlink_to_file target="${FIXam}/${ss_fn}" symlink="${DATA}/temp_orog_data/${ss_fn}" relative="FALSE"

  input_redirect_fn="grid_info.dat"
  cat > "${input_redirect_fn}" <<EOF
${TILE_RGNL}
${CRES:1}
${NH4}
EOF

  print_info_msg "Starting orography file generation..."

  export pgm="orog_gsl"
  . prep_step

  ${APRUN} ${EXECrrfs}/$pgm < "${input_redirect_fn}" >>$pgmout 2>${DATA}/raw_topo/tmp/errfile
  export err=$?; err_chk
  mv ${DATA}/raw_topo/tmp/errfile ${DATA}/raw_topo/tmp/errfile_orog_gsl

  cpreq -p "${CRES}${DOT_OR_USCORE}oro_data_ss.tile${TILE_RGNL}.halo${NH0}.nc" \
           "${CRES}${DOT_OR_USCORE}oro_data_ls.tile${TILE_RGNL}.halo${NH0}.nc" \
           "${COMOUT}/fix"
fi
#
#-----------------------------------------------------------------------
#
# Note that the orography filtering code assumes that the regional grid
# is a GFDLgrid type of grid; it is not designed to handle ESGgrid type
# regional grids.  If the flag "regional" in the orography filtering
# namelist file is set to .TRUE. (which it always is will be here; see
# below), then filtering code will first calculate a resolution (i.e.
# number of grid points) value named res_regional for the assumed GFDLgrid
# type regional grid using the formula
#
#   res_regional = res*stretch_fac*real(refine_ratio)
#
# Here res, stretch_fac, and refine_ratio are the values passed to the
# code via the namelist.  res and stretch_fac are assumed to be the
# resolution (in terms of number of grid points) and the stretch factor
# of the (GFDLgrid type) regional grid's parent global cubed-sphere grid,
# and refine_ratio is the ratio of the number of grid cells on the regional
# grid to a single cell on tile 6 of the parent global grid.  After
# calculating res_regional, the code interpolates/extrapolates between/
# beyond a set of (currently 7) resolution values for which the four
# filtering parameters (n_del2_weak, cd4, max_slope, peak_fac) are provided
# (by GFDL) to obtain the corresponding values of these parameters at a
# resolution of res_regional.  These interpolated/extrapolated values are
# then used to perform the orography filtering.
#
# The above approach works for a GFDLgrid type of grid.  To handle ESGgrid
# type grids, we set res in the namelist to the orography filtering code
# the equivalent global uniform cubed-sphere resolution of the regional
# grid, we set stretch_fac to 1 (since the equivalent resolution assumes
# a uniform global grid), and we set refine_ratio to 1.  This will cause
# res_regional above to be set to the equivalent global uniform cubed-
# sphere resolution, so the filtering parameter values will be interpolated/
# extrapolated to that resolution value.
#
#-----------------------------------------------------------------------
#
if [ "${GRID_GEN_METHOD}" = "GFDLgrid" ]; then
  res="${GFDLgrid_RES}"
  refine_ratio="${GFDLgrid_REFINE_RATIO}"
elif [ "${GRID_GEN_METHOD}" = "ESGgrid" ]; then
  res="${CRES:1}"
  refine_ratio="1"
fi
#
#-----------------------------------------------------------------------
#
# The orography filtering executable replaces the contents of the given
# raw orography file with a file containing the filtered orography.  The
# name of the input raw orography file is in effect specified by the
# namelist variable topo_file; the orography filtering code assumes that
# this name is constructed by taking the value of topo_file and appending
# to it the string ".tile${N}.nc", where N is the tile number (which for
# a regional grid, is always 7).  (Note that topo_file may start with a
# a path to the orography file that the filtering code will read in and
# replace.) Thus, we now copy the raw orography file (whose full path is
# specified by raw_orog_fp) to filter_dir and in the process rename it
# such that its new name:
#
# (1) indicates that it contains filtered orography data (because that
#     is what it will contain once the orography filtering executable
#     successfully exits); and
# (2) ends with the string ".tile${N}.nc" expected by the orography
#     filtering code.
#
#-----------------------------------------------------------------------
#
fn_suffix_without_halo="tile${TILE_RGNL}.nc"
filtered_orog_fn_prefix="${CRES}${DOT_OR_USCORE}filtered_orog"
filtered_orog_fp_prefix="${DATA}/filtered_topo/${filtered_orog_fn_prefix}"
filtered_orog_fp="${filtered_orog_fp_prefix}.${fn_suffix_without_halo}"
cpreq -p "${raw_orog_fp}" "${filtered_orog_fp}"
#
#-----------------------------------------------------------------------
#
# The orography filtering executable looks for the grid file specified
# in the grid mosaic file (more specifically, specified by the gridfiles
# variable in the mosaic file) in the directory in which the executable
# is running.  Recall that above, we already extracted the name of the
# grid file from the mosaic file and saved it in the variable grid_fn,
# and we saved the full path to this grid file in the variable grid_fp.
# Thus, we now create a symlink in the filter_dir directory (where the
# filtering executable will run) with the same name as the grid file and
# point it to the actual grid file specified by grid_fp.
#
#-----------------------------------------------------------------------
#
ln -fs "${grid_fp}" "${DATA}/filtered_topo/${grid_fn}"
#
#-----------------------------------------------------------------------
#
# Create the namelist file (in the filtered_topo directory) that the
# orography filtering executable will read in.
#
#-----------------------------------------------------------------------
#
cat > "${DATA}/filtered_topo/input.nml" <<EOF
&filter_topo_nml
  grid_file = "${mosaic_fp}"
  topo_file = "${filtered_orog_fp_prefix}"
  mask_field = "land_frac"
  regional = .true.
  stretch_fac = ${STRETCH_FAC}
  res = $res
/
EOF
#
#-----------------------------------------------------------------------
#
# Change location to the filtered_topo directory.  This must be done because
# the orography filtering executable looks for a namelist file named
# input.nml in the directory in which it is running (not the directory
# in which it is located).  Thus, since above we created the input.nml
# file in filter_dir, we must also run the executable out of this directory.
#
#-----------------------------------------------------------------------
#
cd "${DATA}/filtered_topo"

# Run the orography filtering executable.
print_info_msg "Starting filtering of orography..."

export pgm="filter_topo"
. prep_step

$APRUN ${EXECrrfs}/$pgm >>$pgmout 2>${DATA}/raw_topo/tmp/errfile
export err=$?; err_chk
mv ${DATA}/raw_topo/tmp/errfile ${DATA}/raw_topo/tmp/errfile_filter_topo
#
# For clarity, rename the filtered orography file in filter_dir
# such that its new name contains the halo size.
#
filtered_orog_fn_orig=$( basename "${filtered_orog_fp}" )
filtered_orog_fn="${filtered_orog_fn_prefix}.${fn_suffix_with_halo}"
filtered_orog_fp=$( dirname "${filtered_orog_fp}" )"/${filtered_orog_fn}"
mv "${filtered_orog_fn_orig}" "${filtered_orog_fn}"
cpreq -p "${filtered_orog_fp}" "${COMOUT}/fix/${CRES}${DOT_OR_USCORE}oro_data.tile${TILE_RGNL}.halo${NHW}.nc"

cd ${DATA}

print_info_msg "Filtering of orography complete."
#
#-----------------------------------------------------------------------
#
# Partially "shave" the halo from the (filtered) orography file having a
# wide halo to generate two new orography files -- one without a halo and
# another with a 4-cell-wide halo.  These are needed as inputs by the
# surface climatology file generation code (sfc_climo; if it is being
# run), the initial and boundary condition generation code (chgres_cube),
# and the forecast model.
#
#-----------------------------------------------------------------------
#
# Set the full path to the "unshaved" orography file, i.e. the one with
# a wide halo.  This is the input orography file for generating both the
# orography file without a halo and the one with a 4-cell-wide halo.
#
unshaved_fp="${filtered_orog_fp}"
#
# We perform the work in shave_dir, so change location to that directory.
# Once it is complete, we move the resultant file from shave_dir to COMOUT.
#
cd "${DATA}/shave_tmp"
#
# Create an input namelist file for the shave executable to generate
# orography files with varios halos from the one with a wide halo.
#
export pgm="shave"

halo_num_list=('0' '4')
halo_num_list[${#halo_num_list[@]}]="${NHW}"
for halo_num in "${halo_num_list[@]}"; do

  print_info_msg "Shaving filtered orography file with ${halo_num}-cell-wide halo..."
  nml_fn="input.shave.orog.halo${halo_num}"
  shaved_fp="${DATA}/shave_tmp/${CRES}${DOT_OR_USCORE}oro_data.tile${TILE_RGNL}.halo${halo_num}.nc"
  printf "%s %s %s %s %s\n" \
  $NX $NY ${halo_num} \"${unshaved_fp}\" \"${shaved_fp}\" \
  > ${nml_fn}

  . prep_step

  $APRUN ${EXECrrfs}/$pgm < ${nml_fn} >>$pgmout 2>${DATA}/raw_topo/tmp/errfile
  export err=$?; err_chk
  mv ${DATA}/raw_topo/tmp/errfile ${DATA}/raw_topo/tmp/errfile_shave_${halo_num}
  cpreq -p ${shaved_fp} ${COMOUT}/fix
done

cd ${DATA}
#
#-----------------------------------------------------------------------
#
# Print message indicating successful completion of script.
#
#-----------------------------------------------------------------------
#
print_info_msg "
========================================================================
Orography files with various halo widths generated successfully!!!

Exiting script:  \"${scrfunc_fn}\"
In directory:    \"${scrfunc_dir}\"
========================================================================"
#
#-----------------------------------------------------------------------
#
# Restore the shell options saved at the beginning of this script/function.
#
#-----------------------------------------------------------------------
#
{ restore_shell_opts; } > /dev/null 2>&1

