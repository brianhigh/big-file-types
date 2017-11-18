# Find max of max daily temperatures and min of min daily temperatures
# for 20 MACAv2 climate models.

# ------
# Setup
# ------

# Clear the workspace.
rm(list=ls())

# Load pacman into memory, installing as needed.
my_repo <- 'http://cran.r-project.org'
if (!require("pacman")) {install.packages("pacman", repos = my_repo)}

# Load the other packages, installing as needed.
pacman::p_load(dplyr, ggplot2, data.table)

# --------------
# Configuration
# --------------

# The path to the input data folder containg the XDF files.
input.folder <- 'E:/tip/data/Temp/xdf'
setwd(input.folder)

models <- c('bcc-csm1-1',
            'bcc-csm1-1-m',
            'BNU-ESM',
            'CanESM2',
            'CCSM4',
            'CNRM-CM5',
            'CSIRO-Mk3-6-0',
            'GFDL-ESM2G',
            'GFDL-ESM2M',
            'HadGEM2-CC365',
            'HadGEM2-ES365',
            'inmcm4',
            'IPSL-CM5A-LR',
            'IPSL-CM5A-MR',
            'IPSL-CM5B-LR',
            'MIROC5',
            'MIROC-ESM',
            'MIROC-ESM-CHEM',
            'MRI-CGCM3',
            'NorESM1-M'
)

# -------------
# Main Routine
# -------------

system.time(results <- lapply(models, function(mod) {
    xdf.dso <- RxXdfData(mod)
    df.rxs <- rxSummary(~tasmax:scenario + tasmin:scenario, 
                                   data=xdf.dso, 
                                   removeZeroCounts = TRUE, 
                                   summaryStats=c("Max", "Min"))
    df.rxs$categorical[[1]][c('scenario', 'Max')] %>% 
        full_join(df.rxs$categorical[[2]][c("scenario", 'Min')],
                  by = 'scenario') %>% 
        rename(maxtmax=Max, mintmin=Min) %>% mutate(model=mod)
}))
##  user   system  elapsed 
##  1.59     3.96 11521.55

dt <- rbindlist(results)

#fwrite(dt, "maxmin.csv")
write.csv(x = dt, file = "maxmin.csv", row.names = FALSE)
