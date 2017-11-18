# Test performance and memory usage of MonetDBLite, XDF, CSV, and SQLite.
# 2017-11-14 high@uw.edu

# ------
# Setup
# ------

# Clear the workspace.
rm(list=ls())

# Load pacman into memory, installing as needed.
my_repo <- 'http://cran.r-project.org'
if (!require("pacman")) {install.packages("pacman", repos = my_repo)}

# Load the other packages, installing as needed.
pacman::p_load(dplyr, dbplyr, pryr, data.table, DBI, MonetDBLite, Xmisc)

# Close all MonetDB sessions, if any.
MonetDBLite:::monetdb_embedded_shutdown()

# Set folder paths.
setwd('E:/tip/data/Temp/mdblite')
dbdir <- 'IPSL-CM5B-LR'

# MonetDBLite

# dbplr tests

# The dbplyr package provides a means to convert an operation of dplyr commands
# to a SQL statement. We will use this feature to perform queries on the 
# database in order to compare performance and complexity with other approaches.

# We will perform a query on our database to find the maximum of the daily
# maximum temperature and the minimum of the daily minimum temperature.

# Show the size of the database in GB as it is stored persistently on the disk.

# dir_size_gb(): Function to calculate directory size on non-Windows systems.
dir_size_gb <- function(dirpath) {
    if (is.dir(dirpath) == TRUE) {
        sum(file.info(
            list.files(dirpath, all.files = TRUE, 
                       recursive = TRUE))$size) / 1024 / 1024 / 1024
    }
}

# win_dir_size_gb(): Function to calculate directory size on Windows systems.
win_dir_size_gb <- function(dirpath) {
    if (is.dir(dirpath) == TRUE) {
        mydir <- getwd()
        setwd(dirpath)
        system('powershell 
               (Get-ChildItem "." -Recurse -Force | \
               Measure-Object -Property Length -Sum).Sum/1GB'
        )
        setwd(mydir)
    }
}

# show_dir_size(): Function to run appropriate OS-specific dir_Size function.
show_dir_size <- function(dbdir) {
    switch(Sys.info()[['sysname']],
           Windows = win_dir_size_gb(dbdir),
           Linux  = dir_size_gb(dbdir),
           Darwin = dir_size_gb(dbdir)
    )
}

# Show database size in GB. This will increase as it caches queries.
show_dir_size(dbdir)
## 72.5454418193549

# Connect to database for use with dbplyr.
system.time( ms <- MonetDBLite::src_monetdblite(dbdir) )
object_size(ms)
## 2.3 kB

# Connect to table using "tbl" interface, which enables dbplyr capabilities.
system.time( mt <- tbl(ms, 'metdata') )
##   user  system elapsed 
##   0.53    7.35    9.79 

object_size(mt)
## 4.09 kB

# Find max and min temps grouped by scenario using dplyr functions.
# We do not have to use "na.rm = TRUE" with max() and min(), as that is
# the default behavior with MonetDBLite's MAX() and MIN() functions in SQL.
system.time( 
    t_grouped <- mt %>% 
        filter(tasmax != 0, tasmin != 0) %>% 
        group_by(scenario) %>% 
        summarise(maxtmax=max(tasmax), mintmin=min(tasmin)) 
)
##   user  system elapsed 
##   0.05    0.00    0.04 

system.time( print(t_grouped) )
## # Source:   lazy query [?? x 3]
## # Database: MonetDBEmbeddedConnection
##     scenario  maxtmax  mintmin
##        <chr>    <dbl>    <dbl>
## 1 historical 317.4471 232.6383
## 2      rcp45 321.2524 231.1474
## 3      rcp85 323.5079 230.2163
##   user  system elapsed 
## 421.78 2663.68  780.28 


# Show database size in GB. This will likely have changed by a few GB.
show_dir_size(dbdir)
## 69.6426818305627

# Remove this output variable, as we no longer need it.
rm(t_grouped)

# Close all MonetDB sessions.
MonetDBLite:::monetdb_embedded_shutdown()

# SQL Tests

# Connect to database for use with SQL.
system.time( con <- dbConnect(MonetDBLite::MonetDBLite(), dbdir) )
##   user  system elapsed 
##   0.72    3.09    3.84 

# List tables.
dbListTables(con)
## [1] "metdata"

# List fields in a table.
dbListFields(con, "metdata")
## [1] "lon"      "lat"      "date"     "scenario" "tasmax"   "tasmin" 

# Show the table columns and their data types using SQL.
table_column_info <- dbGetQuery(con, 
                                'SELECT name AS column_name, 
                                     type as column_data_type 
                                 FROM "sys"."columns" 
                                 WHERE table_id = ( 
                                 SELECT id AS TABLE_ID 
                                 FROM "sys"."tables" 
                                 WHERE name = \'metdata\' 
                                 and schema_id = (SELECT id AS SCHEMA_ID 
                                 FROM "sys"."schemas" 
                                 WHERE name = \'sys\')) 
                                 ORDER BY number;' 
                                )
table_column_info
##   column_name column_data_type
## 1         lon           double
## 2         lat           double
## 3        date             date
## 4    scenario             clob
## 5      tasmax           double
## 6      tasmin           double

# Find max and min temps for each scenario using SQL.
system.time( 
    t_grouped <- dbGetQuery(con, 
                            'SELECT scenario, 
                                 MAX(tasmax) AS maxtmax, 
                                 MIN(tasmin) AS mintmin  
                             FROM metdata 
                             WHERE NOT tasmax = 0 AND NOT tasmin = 0 
                             GROUP BY scenario;'
    )
)
##    user  system elapsed 
##  277.23 2833.37  686.75 

t_grouped
##     scenario  maxtmax  mintmin
## 1 historical 317.4471 232.6383
## 2      rcp45 321.2524 231.1474
## 3      rcp85 323.5079 230.2163

# In-memory tests

# Connect to the database file.
system.time( con <- dbConnect(MonetDBLite::MonetDBLite(), dbdir) )
## user  system elapsed 
## 0.11    3.33    3.51

# Copy the entire table into an in-memory tbl.
system.time(inmem.tbl <- as.tbl(dbReadTable(con, "metdata")))
## user  system elapsed 
## 110.65  116.41  227.08

object_size(inmem.tbl)
## 91.2 GB

str(inmem.tbl)
## Classes ‘tbl_df’, ‘tbl’ and 'data.frame':       1899860160 obs. of  6 variables:
##  $ lon     : num  235 235 235 235 235 ...
##  $ lat     : num  45.1 45.1 45.1 45.1 45.1 ...
##  $ date    : Date, format: "1950-01-01" "1950-01-02" ...
##  $ scenario: chr  "historical" "historical" "historical" "historical" ...
##  $ tasmax  : num  NA NA NA NA NA NA NA NA NA NA ...
##  $ tasmin  : num  NA NA NA NA NA NA NA NA NA NA ...

# Perform previous query on the entire in-memory tbl.
system.time(
    t_grouped_inmem.tbl <- inmem.tbl %>% 
        filter(tasmax != 0, tasmin != 0) %>% 
        group_by(scenario) %>% 
        summarise(maxtmax=max(tasmax, na.rm = TRUE), 
                  mintmin=min(tasmin, na.rm = TRUE))
)
## user  system elapsed 
## 375.20  121.50  497.17 
 
t_grouped_inmem.tbl
## # A tibble: 3 x 3
##     scenario  maxtmax  mintmin
##        <chr>    <dbl>    <dbl>
## 1 historical 317.4471 232.6383
## 2      rcp45 321.2524 231.1474
## 3      rcp85 323.5079 230.2163

# Remove variables which are no longer needed.
rm(t_grouped_inmem.tbl)
rm(inmem.tbl)

# Copy the entire table into an in-memory data.frame.
system.time(inmem.df <- dbReadTable(con, "metdata"))
##  user  system elapsed 
##  111.91   76.16  188.18 
 
str(inmem.df)
## 'data.frame':   1899860160 obs. of  6 variables:
##  $ lon     : num  235 235 235 235 235 ...
##  $ lat     : num  45.1 45.1 45.1 45.1 45.1 ...
##  $ date    : Date, format: "1950-01-01" "1950-01-02" ...
##  $ scenario: chr  "historical" "historical" "historical" "historical" ...
##  $ tasmax  : num  NA NA NA NA NA NA NA NA NA NA ...
##  $ tasmin  : num  NA NA NA NA NA NA NA NA NA NA ...
 
object_size(inmem.df)
## 91.2 GB
 
# Perform previous query on the entire in-memory data.frame.
system.time(
    t_grouped_inmem.tbl <- inmem.df %>% 
        filter(tasmax != 0, tasmin != 0) %>% 
        group_by(scenario) %>% 
        summarise(maxtmax=max(tasmax, na.rm = TRUE), 
                  mintmin=min(tasmin, na.rm = TRUE))
)
##    user  system elapsed 
##  384.38  124.87  509.66 
 
t_grouped_inmem.tbl
## # A tibble: 3 x 3
##     scenario  maxtmax  mintmin
##        <chr>    <dbl>    <dbl>
## 1 historical 317.4471 232.6383
## 2      rcp45 321.2524 231.1474
## 3      rcp85 323.5079 230.2163
 
# Remove variables which are no longer needed.
rm(t_grouped_inmem.tbl)
rm(inmem.df)

# Copy the table into an in-memory data.table.
system.time(inmem.dt <- as.data.table(dbReadTable(con, "metdata")))
##   user  system elapsed 
## 319.77 1203.30  882.41

object_size(inmem.dt)
## 91.2 GB

str(inmem.dt)
## Classes ‘data.table’ and 'data.frame':	1899860160 obs. of  6 variables:
##     $ lon     : num  235 235 235 235 235 ...
## $ lat     : num  45.1 45.1 45.1 45.1 45.1 ...
## $ date    : Date, format: "1950-01-01" "1950-01-02" ...
## $ scenario: chr  "historical" "historical" "historical" "historical" ...
## $ tasmax  : num  NA NA NA NA NA NA NA NA NA NA ...
## $ tasmin  : num  NA NA NA NA NA NA NA NA NA NA ...
## - attr(*, ".internal.selfref")=<externalptr>

# Perform previous query on the in-memory data.table.
system.time(
    t_grouped_inmem.dt <- 
        inmem.dt[tasmax != 0 & tasmin != 0, 
                 .(maxtmax=max(tasmax, na.rm = TRUE), 
                   mintmin=min(tasmin, na.rm = TRUE)), 
                 by = list(scenario)]
)
##   user  system elapsed 
## 166.36   40.34  195.96

t_grouped_inmem.dt
##      scenario  maxtmax  mintmin
## 1: historical 317.4471 232.6383
## 2:      rcp45 321.2524 231.1474
## 3:      rcp85 323.5079 230.2163

# Remove variables which are no longer needed.
rm(inmem.dt)

# Disconnect from the database.
dbDisconnect(con, shutdown=TRUE)

# Show database size in GB. It's probably several GB larger now.
show_dir_size(dbdir)
## 96.4321838477626

# Comparisons with other formats

# Show the size of the file in GB as it is stored persistently on the disk.

# file_size_gb(): Function to calculate file size on non-Windows systems.
file_size_gb <- function(filepath) {
    file.info(filepath)$size / 1024 / 1024 / 1024
}

# win_file_size_gb(): Function to calculate file size on Windows systems.
win_file_size_gb <- function(filepath) {
    system(paste0('powershell (Get-Item ', filepath, 
                  ' | Measure-Object -Property Length -Sum).Sum/1GB', sep=''))
}

# show_file_size(): Function to run appropriate OS-specific file_Size function.
show_file_size <- function(dbdir) {
    switch(Sys.info()[['sysname']],
           Windows = win_file_size_gb(dbdir),
           Linux  = file_size_gb(dbdir),
           Darwin = file_size_gb(dbdir)
    )
}

# XDF: Native filetype for MS Machine Learning Server and RevoScaleR functions.

# Set folder paths.
setwd('//pacific/tip/data/Temp/xdf')
dbfile <- 'IPSL-CM5B-LR.xdf'

# Show size of XDF file.
show_file_size(dbfile)
## 10.9603597745299

# Open the XDF file as a data source object, a pointer to a file on disk.
#system.time(xdf.dso <- rxDataStep(inData=dbfile, outFile=dbfile, 
#                                  overwrite=TRUE))
system.time(xdf.dso <- RxXdfData(dbfile))
##   user  system elapsed 
##   0.03    0.00    0.03

object_size(xdf.dso)
## 82.5 kB

# Show size of XDF file after import.
show_file_size(dbfile)
## 10.9603597745299

# Get metadata about table in the XDF file.
system.time(xdf.info <- rxGetInfo(xdf.dso, getVarInfo = TRUE))
##   user  system elapsed 
##   0.67    0.02    0.72

xdf.info
## File name: E:\tip\data\Temp\xdf\IPSL-CM5B-LR.xdf 
## Number of observations: 1899860160 
## Number of variables: 6 
## Number of blocks: 50 
## Compression type: zlib 
## Variable information: 
## Var 1: lon, Type: numeric, Low/High: (235.2695, 243.9360)
## Var 2: lat, Type: numeric, Low/High: (45.1044, 49.3127)
## Var 3: date, Type: Date, Low/High: (1950-01-01, 2099-12-31)
## Var 4: scenario
## 3 factor levels: historical rcp45 rcp85
## Var 5: tasmax, Type: numeric, Low/High: (233.4706, 323.5079)
## Var 6: tasmin, Type: numeric, Low/High: (230.2163, 308.0072)

# Perform previous query on the data source object using rxSummary.
system.time(
    t_grouped_xdf.rxs <- rxSummary(~tasmax:scenario + tasmin:scenario, 
                                   data=xdf.dso, 
                                   removeZeroCounts = TRUE, 
                                   summaryStats=c("Max", "Min"))
)
## Rows Read: 1899860160, Total Rows Processed: 1899860160, 
##     Total Chunk Time: 331.039 seconds 
## Computation time: 573.832 seconds.
##   user  system elapsed 
##   0.56    0.13  574.41

print(t_grouped_xdf.rxs)
## Call:
##     rxSummary(formula = ~tasmax:scenario + tasmin:scenario, data = xdf.dso, 
##               summaryStats = c("Max", "Min"), removeZeroCounts = TRUE)
## 
## Summary Statistics Results for: ~tasmax:scenario + tasmin:scenario
## Data: xdf.dso (RxXdfData Data Source)
## File name: IPSL-CM5B-LR.xdf
## Number of valid observations: 1899860160 
## 
## Name            Min      Max     
## tasmax:scenario 233.4706 323.5079
## tasmin:scenario 230.2163 308.0072
## 
## Statistics by category (3 categories):
##     
##     Category                       scenario   Min      Max     
## tasmax for scenario=historical historical 239.4761 317.4471
## tasmax for scenario=rcp45      rcp45      235.1420 321.2524
## tasmax for scenario=rcp85      rcp85      233.4706 323.5079
## 
## Statistics by category (3 categories):
##     
##     Category                       scenario   Min      Max     
## tasmin for scenario=historical historical 232.6383 302.2227
## tasmin for scenario=rcp45      rcp45      231.1474 305.1198
## tasmin for scenario=rcp85      rcp85      230.2163 308.0072

# Rearrange the summary output to match the format of our previous results.
t_grouped_xdf <- t_grouped_xdf.rxs$categorical[[1]][c('scenario', 'Max')] %>% 
    full_join(t_grouped_xdf.rxs$categorical[[2]][c("scenario", 'Min')],
              by = 'scenario') %>% rename(maxtmax=Max, mintmin=Min)
t_grouped_xdf
## scenario  maxtmax  mintmin
## 1 historical 317.4471 232.6383
## 2      rcp45 321.2524 231.1474
## 3      rcp85 323.5079 230.2163

# Copy the table into an in-memory data.frame.
system.time(inmem.df <- rxReadXdf(dbfile))
## Rows Processed: 1899860160
## Time to read data file: 653.71 secs.
## Time to convert to data frame: 429.02 secs.
##   user  system elapsed 
##  76.86  262.60 1474.77 

object_size(inmem.df)
## 83.6 GB

str(inmem.df)
#'data.frame':	1899860160 obs. of  6 variables:
#$ lon     : num  235 235 235 235 235 ...
#$ lat     : num  45.1 45.1 45.1 45.1 45.1 ...
#$ date    : Date, format: "1950-01-01" "1950-01-02" ...
#$ scenario: Factor w/ 3 levels "historical","rcp45",..: 1 1 1 1 1 1 1 1 1 1 ...
#$ tasmax  : num  NA NA NA NA NA NA NA NA NA NA ...
#$ tasmin  : num  NA NA NA NA NA NA NA NA NA NA ...

# Perform previous query on the entire in-memory data.frame using dplyr.
system.time(
    t_grouped_inmem.tbl <- inmem.df %>% 
        filter(tasmax != 0, tasmin != 0) %>% 
        group_by(scenario) %>% 
        summarise(maxtmax=max(tasmax, na.rm = TRUE), 
                  mintmin=min(tasmin, na.rm = TRUE))
)
##   user  system elapsed 
## 248.85   71.51  320.88 

t_grouped_inmem.tbl
## # A tibble: 3 x 3
##     scenario  maxtmax  mintmin
##       <fctr>    <dbl>    <dbl>
## 1 historical 317.4471 232.6383
## 2      rcp45 321.2524 231.1474
## 3      rcp85 323.5079 230.2163

# Remove variables which are no longer needed.
rm(inmem.df)

# Copy the table into an in-memory data.table.
system.time(inmem.dt <- data.table(rxReadXdf(dbfile)))
## Rows Processed: 1899860160
## Time to read data file: 670.20 secs.
## Time to convert to data frame: 430.23 secs.
##   user  system elapsed 
## 201.08  394.33 1748.18 

object_size(inmem.dt)
## 83.6 GB

str(inmem.dt)
## Classes ‘data.table’ and 'data.frame':  1899860160 obs. of  6 variables:
##  $ lon     : num  235 235 235 235 235 ...
##  $ lat     : num  45.1 45.1 45.1 45.1 45.1 ...
##  $ date    : Date, format: "1950-01-01" "1950-01-02" ...
##  $ scenario: Factor w/ 3 levels "historical","rcp45",..: 1 1 1 1 1 1 1 1 1 1 ...
##  $ tasmax  : num  NA NA NA NA NA NA NA NA NA NA ...
##  $ tasmin  : num  NA NA NA NA NA NA NA NA NA NA ...
##  - attr(*, ".internal.selfref")=<externalptr> 

# Perform previous query on the in-memory data.table using bracket notation.
system.time(
    t_grouped_inmem.dt <- 
        inmem.dt[tasmax != 0 & tasmin != 0, 
                 .(maxtmax=max(tasmax, na.rm = TRUE), 
                   mintmin=min(tasmin, na.rm = TRUE)), 
                 by = list(scenario)]
)
##   user  system elapsed 
## 144.08   34.19  169.43 

t_grouped_inmem.dt
##      scenario  maxtmax  mintmin
## 1: historical 317.4471 232.6383
## 2:      rcp45 321.2524 231.1474
## 3:      rcp85 323.5079 230.2163

rm(inmem.dt)
rm(t_grouped_inmem.dt)

# CSV: Comma-separated variables, plain text, GZipped

# Set folder paths.
setwd('E:/tip/data/Temp/csv')
dbfile <- 'IPSL-CM5B-LR.csv.gz'

# Show size of GZipped CSV file.
show_file_size(dbfile)
## 26.2556150257587

# Read file into data.table. 
system.time(dt <- fread(
    input = paste0('gzip -d -c ', dbfile), 
    sep = ',', header = TRUE, showProgress = FALSE, 
    colClasses=c('numeric', 'numeric', 
                 'character', 'character', 
                 'numeric', 'numeric')))
##     user   system  elapsed 
## 15101.85 10769.56 27975.28 

object_size(dt)
## 91.2 GB

# Perform previous query on the in-memory data.table.
system.time(
    t_grouped.dt <- dt[tasmax != 0 & tasmin != 0, 
                       .(maxtmax=max(tasmax, na.rm = TRUE), 
                       mintmin=min(tasmin, na.rm = TRUE)), 
                       by = list(scenario)]
)
##   user  system elapsed 
## 164.85   34.41  194.44

t_grouped.dt
## scenario  maxtmax  mintmin
## 1: historical 317.4471 232.6383
## 2:      rcp45 321.2524 231.1474
## 3:      rcp85 323.5079 230.2163

# Remove variables which are no longer needed.
rm(dt)
rm(t_grouped.dt)

# Read CSV file using read_csv() from readr package. (Run from RStudio/Windows)
# library(readr)
# system.time(df <- read_csv(dbfile))
# In RStudio: "Session Aborted"

# Read CSF file using read_csv() from readr package. (Run from Bash on Linux.)
# library(readr)
# setwd('/projects/tip/data/Temp/csv')
# dbfile <- 'IPSL-CM5B-LR.csv.gz'
# system.time(df <- read_csv(dbfile))
## Error: segfault from C stack overflow
## Timing stopped at: 1729 177.9 1909

# CSV: "Comma-separated variables", "plain text".

# Set folder paths.
setwd('E:/tip/data/Temp/csv')
dbfile <- 'CCSM4.csv'

# Show size of CSV file.
show_file_size(dbfile)
## 145.488924086094

# SQLite - Much slower than MonetDBLite!

# Load Packages.
pacman::p_load(RSQLite)

# Set folder paths.
setwd('E:/tip/data/Temp/sqlite')
dbfile <- 'IPSL-CM5B-LR'

# Show size of SQLite file.
show_file_size(dbfile)
## 109.409927368164

mydb <- dbConnect(RSQLite::SQLite(), dbfile)

myqry <- 'SELECT * FROM metdata'
system.time(dt.sqlite <- as.data.table(dbGetQuery(mydb, myqry)))
##    user  system elapsed 
## 4674.23  470.36 5146.21 

object_size(dt.sqlite)
## 91.2 GB

# Remove data object as we are done with it and it is large.
rm(dt.sqlite)

# Repeat as above using 'tbl' as a dbplyr interface to the database.

system.time(tbl.sqlite <- tbl(mydb, 'metdata'))
##  user  system elapsed 
##  0.03    0.00    0.06 

object_size(tbl.sqlite)
## 4.38 kB

# Find max and min temps grouped by scenario using dplyr functions.
# We do not have to use "na.rm = TRUE" with max() and min(), as that is
# the default behavior with MonetDBLite's MAX() and MIN() functions in SQL.
system.time( 
    t_grouped <- tbl.sqlite %>% 
        filter(tasmax != 0, tasmin != 0) %>% 
        group_by(scenario) %>% 
        summarise(maxtmax=max(tasmax), mintmin=min(tasmin)) 
)
##  user  system elapsed 
##  0.13    0.00    0.12 

system.time( print(t_grouped) )
## # Source:   lazy query [?? x 3]
## # Database: sqlite 3.19.3 [E:\tip\data\Temp\sqlite\CCSM4.sqlite]
##     scenario  maxtmax  mintmin
##        <chr>    <dbl>    <dbl>
## 1 historical 317.4471 232.6383
## 2      rcp45 324.9606 228.7205
## 3      rcp85 326.6826 232.5058
##    user  system elapsed 
## 3402.76  954.03 4362.61 

# Show database size in GB.
show_file_size(dbfile)
## 109.409927368164

# Find max and min temps for each scenario using SQL.
system.time( 
    t_grouped <- dbGetQuery(mydb, 
                            'SELECT scenario, 
                                MAX(tasmax) AS maxtmax, 
                                MIN(tasmin) AS mintmin  
                            FROM metdata 
                            WHERE NOT tasmax = 0 AND NOT tasmin = 0 
                            GROUP BY scenario;'
    )
)
##    user  system elapsed 
## 3376.88  959.99 4383.75 

t_grouped
##     scenario  maxtmax  mintmin
## 1 historical 317.4471 232.6383
## 2      rcp45 324.9606 228.7205
## 3      rcp85 326.6826 232.5058

# Disconnect from the SQLite database.
dbDisconnect(mydb)

# Clean up large memory objects which are no longer needed.
rm(tbl.sqlite)
rm(t_grouped)

# Feather: Don't use with this project -- Can't read files into memory!

# Load Packages.
pacman::p_load(feather)

# Set folder paths.
setwd('E:/tip/data/Temp/feather')
#setwd('/projects/tip/data/Temp/feather')
dbfile <- 'CCSM4.feather'

# Write feather file from in-memory object.
system.time(write_feather(df, dbfile))
##   user  system elapsed 
##  99.31   23.45  210.18 

# Remove variables which are no longer needed.
rm(df)

# Show size of feather file.
show_file_size(dbfile)
## 16.676847293973

# Copy the feather file into an in-memory tbl.
system.time(inmem.tbl <- read_feather(dbfile))
# --- Aborts session ---
# Using MS R Open on Windows:
# *** caught segfault *** address 0x7ff9fd7410a8, cause 'invalid permissions'
# Using system-installed standard R on Ubuntu Linux:
# *** caught segfault *** address 0x7fd41deafbe8, cause 'memory not mapped'

# RData: Read the MonetDBLite file, save as RData, and read RData file.

# We will use save() and load() functions. See also: saveRDS() and readRDS().

setwd('E:/tip/data/Temp/mdblite')
dbdir <- 'IPSL-CM5B-LR'
dbfile <- 'IPSL-CM5B-LR.RData'

# Connect to database for use with SQL.
system.time( con <- dbConnect(MonetDBLite::MonetDBLite(), dbdir) )
##  user  system elapsed 
##  0.72    3.09    3.84 

# Copy the entire table into a data.frame.
system.time(inmem.df <- dbReadTable(con, "metdata"))
##   user  system elapsed 
## 111.91   76.16  188.18 

object_size(inmem.df)
## 91.2 GB

# Disconnect from the database.
dbDisconnect(con, shutdown=TRUE)

# Save data.frame as an RData file.
save(inmem.df, file = dbfile)

show_file_size(dbfile)
## 95.8077429551631

# Remove data.frame object.
rm(inmem.df)

# Read the RData file into memory as original data.frame name (inmem.df).
system.time(load(file = dbfile))
##    user  system elapsed 
## 1455.64  183.66 1641.49 

object_size(inmem.df)
## 91.2 GB

# Remove data.frame object.
rm(inmem.df)

