source("classifyTweets.R")

# Wrapper for calling classifyTweets on URL data.
# Builds 1 model per input file. Assumes input file fits in memory.
# Work of the wrapper: 
# -Changes data rows from tweet-URLs to tweets (for classification) and back again.
# -Constructs tweet text "complete_raw_text" from input columns (includes RT, quoted handles and expanded URLs).


# inFile: a tsv.gz (or similar) containing columns tweet_id, tweet_text (and retweet_prefix, quote_of_user_name and quoted_text) and canonical_url.
#   Repeats same tweet on multiple rows (assumed to be sequential!), once per URL. (Doesn't matter if it has only "external" URLs or also twitter_* ones.)
# outFile: a tsv file with same fields as inFile + political_classifier_score and white_terms. See classifierThreshold for which lines.
#   If classifierThreshold is NULL (implied if saveDebuggingColumnsRows is TRUE), keeps all rows. (Will have '.gz' appended to argument provided.)
# keywordFile: used to define the training set, one term (word or phrase) per line. If a tweet contains one of these terms, it's ALWAYS kept (so, 
#   be sure to put only high-precision terms in this file.)
# modelFileOutStem: if non-NULL, we'll save two .rds files beginning with this path + prefix, to allow using same model (including doc->term mapping) on future tweets
#   (plus a 3rd file == a plot of training set scores)
# classifierThreshold: Normally, keep rows with scores above this value. If it's NULL or if saveDebuggingColumnsRows=T, then keep all rows.
# saveDebuggingColumnsRows: flag for printing larger outfile to inspect scores.
filterURLDataUsingClassifier = function(inFile, outFile, keywordFile, modelFileOutStem=NULL, classifierThreshold=.8, saveDebuggingColumnsRows=FALSE,
                                        goFastUseNaiveBayes=F, noTraining=F, loadVectorizer=F) {
    
    startTime = Sys.time()
    print(paste("Run started at", startTime))
    
    # 1. Read data, change to tweet level (from tweet-url level), match against whitelist, tokenize, and build DocumentTermMatrix.
    inData = fread(paste("zcat", inFile), sep = "\t", quote="")
    tweetData = constructTweets(inData)    # contains tweet_id, complete_raw_text
    print(paste("Done constructing tweets at", Sys.time() - startTime))
    
    # 2. All the classification work! Construct training set, tokenize text, train classifier, get predictions from classifier.
    tweetData = classifyTweets(keywordFile, tweetData = tweetData[, .(tweet_id, complete_raw_text)],  modelFileOutStem, startTime, goFastUseNaiveBayes, 
                                noTraining=noTraining, loadVectorizer=loadVectorizer)
    
    # 3. Change back to tweet-url level, apply threshold for filtering, save
    dataWithScores = merge(inData, tweetData, by="tweet_id")
    
    colsWanted = colnames(dataWithScores)
    if (saveDebuggingColumnsRows) {
        classifierThreshold = NULL
    } else {
        # all we add to original is white_terms and political_classifier_score
        colsWanted = setdiff(colsWanted, c("classifier_label", "complete_raw_text", "rest_of_text", "raw_classifier_score", "white_terms"))
    }
    if (! is.null(classifierThreshold)) {
        print(paste("Keeping the", sum(dataWithScores$political_classifier_score >= classifierThreshold), "of", nrow(dataWithScores), 
                    "lines with a classifier score >=", classifierThreshold))
        dataWithScores = dataWithScores[political_classifier_score >= classifierThreshold,]
    }
    fwrite(dataWithScores[, colsWanted, with=F], file=outFile, sep="\t", quote=F)
    system(paste("gzip -f", outFile))
    
}

# Very similar to the one above, but saves a slimmed-down file to use in prediction pipeline: one line per tweet, removes unneeded columns,
# adds count columns.
# Returns filename for filtered tweets.
filterClassifyURLDataSaveAsTweets = function(inFile, outFileStem, keywordFile, modelFileOutStem=NULL, classifierThreshold=.8, saveDebuggingColumnsRows=FALSE,
                                             goFastUseNaiveBayes=F, saveRawCountsFile=T) {

    startTime = Sys.time()
    print(paste("Run started at", startTime))
    
    # 1. Read data, change to tweet level (from tweet-url level), match against whitelist, tokenize, and build DocumentTermMatrix.
    inData = fread(paste("zcat", inFile), sep = "\t", quote="")
    tweetData = constructTweets(inData)    # contains tweet_id, complete_raw_text
    print(paste("Done constructing tweets at", Sys.time() - startTime))
    
    # 2. All the classification work! Construct training set, tokenize text, train classifier, get predictions from classifier.
    # tweetData columns added: classifier_label, white_terms, rest_of_text, raw_classifier_score, political_classifier_score
    tweetData = classifyTweets(keywordFile, tweetData = tweetData[, .(tweet_id, complete_raw_text)],  modelFileOutStem, startTime, goFastUseNaiveBayes)
    
    # 3. Merge back with input data
    firstRowEachTweet = !duplicated(inData$tweet_id)
    dataWithScores = merge(inData[firstRowEachTweet,], tweetData, by="tweet_id")
    
    
    # 4. Compute tweet counts per day and is_retweet (while we still have raw data allowing this).
    dataWithScores[, is_retweet := !is.na(retweet_of_user_id) & !is.na(retweet_of_tweet_id)]
    dataWithScores$unix_date = unclass(as.POSIXct(strptime(dataWithScores$tweet_date, format="%a %b %d %T +0000 %Y", tz="UTC")))
    # How to account for London vs. U.S. time zones? Let's use midnight Eastern.
    # (Alt options: could stick with London/UTC. Or use 5am Eastern? -- might work better wrt Alaska/Hawaii, but would be weirder to explain to people.)
    dataWithScores$date_eastern = substr(as.POSIXlt(dataWithScores$unix_date, origin="1970-01-01"), 1, 10)
    rawCountsPerPersonDay = dataWithScores[, .(num_tweets_by_user_today = .N), by=.(user_id, date_eastern)]
    if (saveRawCountsFile) {  # need to save separately, otherwise people w/o political tweets won't have their num tweets recorded.
        countsFile = paste0(outFileStem, ".counts.csv")
        fwrite(rawCountsPerPersonDay, file=countsFile)
        system(paste("gzip -f", countsFile))
    }
    dataWithScores = merge(dataWithScores, rawCountsPerPersonDay, by=c("user_id", "date_eastern"))
    # no need for this here, since we need to count it later across files 
    #if (! is.null(classifierThreshold)) {
    #    politicalCountsPerPersonDay = dataWithScores[political_classifier_score >= classifierThreshold, 
    #                                                 .(num_political_tweets_by_user_today = .N), by=.(user_id, date_eastern)]
    #    dataWithScores = merge(dataWithScores, politicalCountsPerPersonDay, by=c("user_id", "date_eastern"), all.x=T)
    #}
    
    # 5. Apply threshold for filtering
    if (saveDebuggingColumnsRows) {
        classifierThreshold = NULL
        additionalColsWanted = c("classifier_label", "rest_of_text", "raw_classifier_score")
    } else {
        # all we add to original is white_terms and political_classifier_score
        additionalColsWanted = c()
    }
    if (! is.null(classifierThreshold)) {
        print(paste("Keeping the", sum(dataWithScores$political_classifier_score >= classifierThreshold), "of", nrow(dataWithScores), 
                    "lines with a classifier score >=", classifierThreshold))
        dataWithScores = dataWithScores[political_classifier_score >= classifierThreshold,]
    }
    
    # 4. Get rid of extra columns, save
    colsWanted = c("tweet_id", "user_id", "tweet_date", "date_eastern",
                   "candidate_interaction",  "political_classifier_score", 
                   "white_terms", "complete_raw_text", additionalColsWanted)
    outFile = paste0(outFileStem, ".tsv")
    fwrite(dataWithScores[, colsWanted, with=F], file=outFile, sep="\t", quote=F)
    system(paste("gzip -f", outFile))
    
    return(paste0(outFile, ".gz"))
    
}

# Gathers text + URLs for each tweet
# inData: a data.table (straight from the inFile)
# returns: a data.table with columns tweet_id and complete_raw_text 
constructTweets = function(inData) {
    
    # be a little more precise with URLs than before: attach orig/retweeted ones [expansions] to tweet_text, but quoted ones to quoted_text.
    tweetURLs_orig = inData[where_url_found != 'quoted', .(orig_urls = paste(canonical_url, collapse=" ")), by = tweet_id]
    tweetURLs_quoted = inData[where_url_found == 'quoted', .(quoted_urls = paste(canonical_url, collapse=" ")), by = tweet_id]
    
    # add new urls columns to inData
    tweetData = merge(inData, tweetURLs_orig, all.x=T)  
    tweetData = merge(tweetData, tweetURLs_quoted, all.x=T)  
    # that produced NAs. Change to empty strings.
    tweetData[is.na(orig_urls), orig_urls := '']
    tweetData[is.na(quoted_urls), quoted_urls := '']
    
    # text: Paste back together the RT prefix, the tweet_text + orig_urls, the quoting marker, and the quoted_text + quoted_urls.
    firstRowEachTweet = !duplicated(tweetData$tweet_id)
    # (this is probably slower than the usual way I'd do it, but I wanted to try out the syntax)
    tweetData$quoting = ifelse(tweetData$quote_of_user_name == '', '', paste0("[QTG @", tweetData$quote_of_user_name, "]"))
    
    tweetData = tweetData[firstRowEachTweet, .(tweet_id, raw_text = paste(retweet_prefix, tweet_text, orig_urls, 
                                                                       quoting, quoted_text, quoted_urls))]
    # The whole reason we expanded URLs is because the t.co versions are meaningless. Delete those.
    tweetData$complete_raw_text = gsub("(?<!\\w)https?\\://t\\.co/\\S+", "", tweetData$raw_text, perl=T)
    
    return(tweetData[, .(tweet_id, complete_raw_text)])
    
}

