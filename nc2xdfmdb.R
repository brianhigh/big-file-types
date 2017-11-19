#!/opt/microsoft/rclient/3.4.1/bin/R/Rscript

# Import/Merge NetCDF data for each model to CSV/XDF/SQLite/MonetDBLite files.
# Comment out in2* command in last program block to disable a file output type.
# XDF file output requires Microsoft R Client or Machine Learning Server.
# Tested with Microsoft R Open 3.4.1, R Client packages, version 3.4.1.008. 
# (2017-11-02, Brian High)

# ------
# Setup
# ------

# Clear the workspace.
rm(list=ls())

# Load pacman into memory, installing as needed.
my_repo <- 'http://cran.r-project.org'
if (!require("pacman")) {install.packages("pacman", repos = my_repo)}

# Load the other packages, installing as needed.
pacman::p_load(dplyr, stringr, data.table, ncdf4, raster, RSQLite, MonetDBLite, DBI)

# --------------
# Configuration
# --------------

# The path to the input data folder containg the NetCDF files.
input.folder <- 'E:/tip/data/Temp'

# The path to the output folder, as a subfolder of input folder (above).
xdf.output.folder <- file.path(input.folder, 'xdf')
sqlite.output.folder <- file.path(input.folder, 'sqlite')
csv.output.folder <- file.path(input.folder, 'csv')
mdblite.output.folder <- file.path(input.folder, 'mdblite')

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
mods <- models[1:20]

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

# in2sqlite(): A function to import a data frame into a SQLite file.
in2sqlite <- function(indata, outfile, tablename) {
    # SQLite can't handle the "date" data type, so convert dates to character.
    indata <- indata %>% mutate(`date` = as.character(`date`))
    
    # Open database connection, creating file if it does not already exist.
    mydb <- dbConnect(RSQLite::SQLite(), outfile)
    
    # Save data.table to database and close database file.
    dbWriteTable(mydb, tablename, indata, append = TRUE, row.names = FALSE)
    dbDisconnect(mydb)
}

# in2csv(): A function to export a data table into a CSV file.
in2csv <- function(indata, outfile) {
    fwrite(indata, outfile, append = TRUE, showProgress = FALSE)
}

# in2mdblite(): A function to export a data frame into a MonetDBLite database.
in2mdblite <- function(indata, dbdir, tablename, field.types) {
    # Open database connection, creating database if it does not already exist.
    mydb <- dbConnect(MonetDBLite::MonetDBLite(), dbdir)
    
    # Save data.table to database and close database.
    if (dir.exists(dbdir)) {
        # Warning: We have found appending to MonetDBLite may lose data!
        dbWriteTable(mydb, tablename, indata, row.names = FALSE, append = TRUE)
    }
    else {
        dbWriteTable(mydb, tablename, indata, row.names = FALSE, 
                     field.types = field.types)
    }
    dbDisconnect(mydb, shutdown = TRUE)
}

# -------------
# Main Routine
# -------------

# Set working directory to the input data folder.
setwd(input.folder)

# Create the output data folders if they do not already exist.
dir.create(xdf.output.folder, showWarnings = FALSE)
dir.create(sqlite.output.folder, showWarnings = FALSE)
dir.create(csv.output.folder, showWarnings = FALSE)
dir.create(mdblite.output.folder, showWarnings = FALSE)

if (! dir.exists(xdf.output.folder) & 
    ! dir.exists(sqlite.output.folder) & 
    ! dir.exists(csv.output.folder) & 
    ! dir.exists(mdblite.output.folder)) {
  stop('Aborting: Cannot create output folders.')
}

# Select filenames to process that match the configured variables and models.
files <- data.table(select_files(input.folder, vars, mods))

# Configure variable types for the XDF file(s).
col.classes <- c(lon = 'numeric', lat = 'numeric', date = 'Date', 
                 scenario = 'factor', tasmax = 'numeric', tasmin = 'numeric')
col.info <- list(scenario = list(type = 'factor', 
                                 levels = c('historical', 'rcp45', 'rcp85')))

# Configure variable types for the MonetDBLite file(s).
field.types <- list(lon = 'NUMERIC(19,14)', lat = 'NUMERIC(19,14)', 
                    `date` = 'DATE', scenario = 'VARCHAR(12)', 
                    tasmax = 'NUMERIC(19,14)', tasmin = 'NUMERIC(19,14)')

# Process files for each model selected in the main configuration section.
sapply(sort(unique(files$model)), function(mod) {
    # Note: We will assume that none of these output files already exist.
    xdf.ofn <- file.path(xdf.output.folder, paste0(mod, '.xdf'))
    sqlite.ofn <- file.path(sqlite.output.folder, paste0(mod, '.sqlite'))
    csv.ofn <- file.path(csv.output.folder, paste0(mod, '.csv'))
    mdblite.ofn <- file.path(mdblite.output.folder, paste0(mod))
    
    # Create a vector of unique scenario and startyr combinations.
    scenyrs <- unique(files[ , paste(scenario, startyr, sep = '_')])
    
    # For each scenario/startyr combination, import, merge, and export.
    sapply(scenyrs, function(scenyr) {
        ifnames <- files[model == mod & str_detect(filename, scenyr), filename]
        dt <- Reduce(merge, lapply(ifnames, function(ifn) { 
                  nc2dt(ifn, files[filename == ifn, variable])}))
                  
        # Create output files. Comment-out lines for unwanted output types.
        in2xdf(dt, xdf.ofn, col.classes, col.info)
        #in2sqlite(dt, sqlite.ofn, 'metdata')
        in2csv(dt, csv.ofn)
        #in2mdblite(dt, mdblite.ofn, 'metdata', field.types)
    })
    if (file.exists(csv.ofn) == TRUE) { system(paste0('gzip ', csv.ofn)) }
})


