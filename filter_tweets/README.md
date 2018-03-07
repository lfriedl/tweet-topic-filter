Work in progress.

Roughly, the command line call looks like:


    Rscript -e
    'source("politicalFilterURLData.R")' -e
    'filterURLDataUsingClassifier("/inDir/tweets_with_urls/2016-08-01.tsv.gz",
    "/outDir/tweets_with_urls_political/2016-08-01.tsv",
    "../keyword_data/whitelist.politics3.txt")'
