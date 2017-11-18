#!/bin/bash
#
# Merge MACAv2 NetCDF files using NCO, given a model, ensemble and scenario.
# For more about NCO toolkit, see: http://nco.sourceforge.net/nco.html

# Check for proper usage.
USAGE="Usage: $0 model ensemble scenario"
[ $# -lt 2 ] && echo "$USAGE" && exit 1

# Check for dependencies.
deps=( ncks ncrcat ncrename )
which "${deps[@]}" > /dev/null
[ $? -ne 0 ] && echo "You must have installed: ${deps[@]}" && exit 1

# Configuration
mod_ens_scen="${1}_${2}_${3}"
scenario="$3"
vars=( tasmax tasmin ) 
ncvar='air_temperature'

# Set start year.
start_yr='1950_1954'
[ ! "$scenario" == "historical" ] && start_yr='2006_2010'

# Combine files for this model, etc., for all year ranges for each variable.
for v in ${vars[@]}; do \
    # Rename the first file so that we can use the original name as output.
    mv macav2metdata_${v}_${mod_ens_scen}_${start_yr}_CONUS_daily.nc \
        macav2metdata_${v}_${mod_ens_scen}_${start_yr}_CONUS_daily.nc.sav

    # Set time as the record dimension by converting from fixed to unlimited.
    ncks --mk_rec_dmn time \
        macav2metdata_${v}_${mod_ens_scen}_${start_yr}_CONUS_daily.nc.sav \
        macav2metdata_${v}_${mod_ens_scen}_${start_yr}_CONUS_daily.nc

   # Combine all files for this model, scenario, and variable.
    ncrcat macav2metdata_${v}_${mod_ens_scen}_*.nc \
        ${v}_${mod_ens_scen}.nc

    # Rename the first file back to its original name.
    mv macav2metdata_${v}_${mod_ens_scen}_${start_yr}_CONUS_daily.nc.sav \
        macav2metdata_${v}_${mod_ens_scen}_${start_yr}_CONUS_daily.nc

    # Rename the variable so that it will be distinct when merged.
    ncrename -v ${nc_var},${v} ${v}_${mod_ens_scen}.nc
done

# Merge variables from first file into second, by all dimensions, as union.
ncks -A ${vars[0]}_${mod_ens_scen}.nc ${vars[1]}_${mod_ens_scen}.nc

# Reset record dimension (time) from unlimited to fixed.
ncks -4 --fix_rec_dmn time \
    ${vars[1]}_${mod_ens_scen}.nc \
    ${mod_ens_scen}.nc

# Remove temporary files.
rm -f {${vars[0]},${vars[1]}}_${mod_ens_scen}.nc

# Note: You can combine the resulting files (for multiple scenarios), e.g.:
#   ncecat -G scenario_ bcc-csm1-1-m_r1i1p1_* bcc-csm1-1-m_r1i1p1.nc
# Where each scenario will be stored as a separate group in the output file.
