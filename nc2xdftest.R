#!/opt/microsoft/rclient/3.4.1/bin/R/Rscript

# Import/Merge NetCDF data for each model and append XDF, 5 yrs at a time.
# XDF file output requires Microsoft R Client or Machine Learning Server.
# Tested with Microsoft R Open 3.4.1, R Client packages, version 3.4.1.008. 
# (2017-11-19, Brian High)

# ------
# Setup
# ------

# Clear the workspace.
rm(list=ls())

# Load pacman into memory, installing as needed.
my_repo <- 'http://cran.r-project.org'
if (!require("pacman")) {install.packages("pacman", repos = my_repo)}

# Load the other packages, installing as needed.
pacman::p_load(dplyr, stringr, data.table, raster)

# --------------
# Configuration
# --------------

# The path to the input data folder containg the NetCDF files.
input.folder <- '//pacific/tip/data/Temp'

# The path to the output folder, as a subfolder of input folder (above).
xdf.output.folder <- file.path(input.folder, 'xdf')

# Select which variables(s) you want to compile.
varnames <- c('tasmax', 'tasmin')
vars <- varnames[1:2]
# See "Configure variable types" below if you change this!

# Select which model(s) you want to compile.
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

# Choose one or more models by subsetting the above vector.
mods <- models[15]

# ----------
# Functions
# ----------

# select_files(): A function to list, parse, and subset input filenames.
select_files <- function(input.folder, vars, mods) {
    # Get a list of files from the input folder matching the "nc" file suffix.
    files <- list.files(path=input.folder, pattern='*\\.nc')
    
    # Parse filenames to create a data table of NetCDF files and their metadata.
    # Assume filename consists of 9 underscore-delimted fields.
    files.dt <- files %>% strsplit('_') %>% unlist() %>% t() %>% 
        matrix(ncol = length(files), nrow = 9) %>% t() %>% 
        data.table()
    names(files.dt) <- c('method', 'variable', 'model', 'ensemble', 'scenario', 
                         'startyr', 'endyr', 'region', 'period')
    
    # Subset for only those files which match selected variables and models.
    myfiles.dt <- files.dt %>% filter(variable %in% vars, model %in% mods)
    if (! nrow(files.dt) > 0) {
        stop('Aborting: Variables and models do not match NetCDF files.')
    }
    
    # Reconstruct filenames for files selected for processing.
    myfiles.dt$filename <- sapply(1:nrow(myfiles.dt), 
                                  function(x) paste0(myfiles.dt[x,], 
                                                     collapse='_'))
    
    # Clean up "period" column by removing file suffix.
    myfiles.dt$period <- gsub('\\.nc$', '', myfiles.dt$period)
    
    myfiles.dt
}

# nc2dt(): A function to import a NetCDF file into a data.table.
nc2dt <- function(infile, varname) {
    layerlist <- brick(infile)
    dt <- rbindlist(lapply(1:nlayers(layerlist), function(layernum) { 
        as.data.frame(layerlist[[layernum]], long=TRUE, xy = TRUE) }), 
        use.names=TRUE, fill=TRUE)
    names(dt) <- c('lon', 'lat', 'date', varname)
    dt$scenario <- gsub('^.*_(historical|rcp[0-9]+)_.*$', '\\1', infile)
    dt
}

# in2xdf(): A function to export a file or data frame into a XDF file.
in2xdf <- function(indata, outfile, col.classes, col.info) {
    # Configuration
    my.overwrite = TRUE
    my.append = 'none'
    
    # If the file exists, configure to append to it, otherwise create it.
    if(file.exists(outfile)) { 
        my.overwrite = FALSE
        my.append = 'rows'
    }
    
    # Import data into an XDF file.
    xdf <- rxImport(inData=indata, outFile=outfile, reportProgress = 1, 
                    append = my.append, overwrite = my.overwrite, 
                    colInfo = col.info, colClasses = col.classes,
                    stringsAsFactors = FALSE, xdfCompressionLevel = 5)
}

# -------------
# Main Routine
# -------------

# Set working directory to the input data folder.
setwd(input.folder)

# Create the output data folder if it does not already exist.
dir.create(xdf.output.folder, showWarnings = FALSE)

if (! dir.exists(xdf.output.folder)) {
    stop('Aborting: Cannot create output folders.')
}

# Select filenames to process that match the configured variables and models.
files <- data.table(select_files(input.folder, vars, mods))

# Configure variable types for the XDF file(s).
col.classes <- c(lon = 'numeric', lat = 'numeric', date = 'Date', 
                 scenario = 'factor', tasmax = 'numeric', tasmin = 'numeric')
col.info <- list(scenario = list(type = 'factor', 
                                 levels = c('historical', 'rcp45', 'rcp85')))

# Process files for each model selected in the main configuration section.
system.time(sapply(sort(unique(files$model)), function(mod) {
    # Start with a fresh XDF file. Remove pre-existing XDF file, if any.
    xdf.ofn <- file.path(xdf.output.folder, paste0(mod, '.xdf'))
    if (file.exists(xdf.ofn)) { unlink(xdf.ofn) }
    
    # Create a vector of unique scenario and startyr combinations.
    scenyrs <- unique(files[, paste(scenario, startyr, sep = '_')])
    
    # For each scenario/startyr combination, import, merge, and export.
    sapply(scenyrs, function(scenyr) {
        ifnames <- files[model == mod & str_detect(filename, scenyr), filename]
        print(paste("Importing variable(s) from NetCDF file(s):", scenyr))
        print(system.time(dt <- Reduce(merge, lapply(ifnames, function(ifn) { 
            nc2dt(ifn, files[filename == ifn, variable])}))))
        
        # Create/append XDF output file.
        print(paste("Appending", scenyr, "to XDF file:", xdf.ofn))
        print(system.time(in2xdf(dt, xdf.ofn, col.classes, col.info)))
    })
}))

