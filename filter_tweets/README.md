
Easiest to call from within R, as follows:

    > source("politicalFilterURLData.R")
    > filterURLDataUsingClassifier(
    	inFile = "../example_data/inData.tsv.gz", 
    	outFile = "../example_data/outFile.tsv", 
    	keywordFile = "../keyword_data/whitelist.politics3.txt")

Other flags may be useful too; see the source code for documentation.

The same call can be made from the command line as:

    Rscript -e 'source("politicalFilterURLData.R")' -e
    'filterURLDataUsingClassifier("../example_data/inData.tsv.gz",
    "../example_data/outFile.tsv",
    "../keyword_data/whitelist.politics3.txt")'

