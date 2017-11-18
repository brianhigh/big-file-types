#!/opt/microsoft/rclient/3.4.1/bin/R/Rscript

# For each XDF file, read and export data into a MonetDBLite database file.
# Processing XDF files requires Microsoft R Client or Machine Learning Server.
# Tested with Microsoft R Open 3.4.1, R Client packages, version 3.4.1.008. 
# (2017-11-12, Brian High)

# Clear the workspace.
rm(list=ls())

# Load pacman into memory, installing as needed.
my_repo <- 'http://cran.r-project.org'
if (!require("pacman")) {install.packages("pacman", repos = my_repo)}

# Load the other packages, installing as needed.
pacman::p_load(DBI, MonetDBLite)

# Function xdf2mdblite() reads in a XDF file and saves to a MonetDBLite file.
xdf2mdblite <- function(db, indir, outdir) {
    # Read XDF file into data frame.
    df <- rxReadXdf(file.path(indir, paste0(db, '.xdf')))

    # Open database connection, creating database if it does not already exist.
    mondb <- dbConnect(MonetDBLite::MonetDBLite(), file.path(outdir, db))
    
    # Save data.table to database and close database.
    dbWriteTable(mondb, 'metdata', df, row.names = FALSE)
    dbDisconnect(mondb, shutdown = TRUE)
}

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

# Select models to process.
mods <- models[1:20]

# Select location of parent data folder.
data.folder <- 'E:/tip/data/Temp'
setwd(data.folder)

# Specify names of data subfolders for each file type.
input.folder <- file.path(data.folder, 'xdf')
output.folder <- file.path(data.folder, 'mdblite')

# Process data files for each selected model.
sapply(mods, function(mod) { xdf2mdblite(mod, input.folder, output.folder) })

