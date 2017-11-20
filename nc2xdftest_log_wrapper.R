# Log execution output of nc2xdftest.R to a file.
# Modified from thread: https://stackoverflow.com/questions/7096989
# In a reply by Tommy: https://stackoverflow.com/users/662787/tommy

con <- file("nc2xdftest.log")
sink(con, append=TRUE)
sink(con, append=TRUE, type="message")

# This will echo all input and not truncate 150+ character lines...
source("nc2xdftest.R", echo=TRUE, max.deparse.length=10000)

# Restore output to console
sink() 
sink(type="message")

# And look at the log...
#cat(readLines("nc2xdftest.log"), sep="\n")
#
# And extract the execution times...
#$ egrep '^[ ]{1,2}[0-9]+'nc2xdftest.log > elapsed_read.txt
#$ egrep '^[ ]{3}[0-9]+'nc2xdftest.log > elapsed_write.txt
