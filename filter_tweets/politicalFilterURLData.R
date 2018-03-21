source("classifyTweets.R")
library(bit64)

# Wrapper for calling classifyTweets on URL data. (function filterURLDataUsingClassifier)
# Builds 1 model per input file. Assumes input file fits in memory.
# Work of the wrapper: 
# -Changes data rows from tweet-URLs to tweets (for classification) and back again.
# -Constructs tweet text "complete_raw_text" from input columns (includes RT, quoted handles and expanded URLs).


# Quick utility function. (Note: loses dates, users and other tweet-level data.)
# inFile: as for filterURLDataUsingClassifier().
# outFile: tsv will contain just 2 columns: tweet_id and complete_raw_text. (File will have '.gz' appended to argument provided.)
changeInfileToTweets = function(inFile, outFile) {
    inData = fread(paste("gzcat", inFile), sep = "\t", quote="'")
    tweetData = constructTweets(inData)    # contains tweet_id, complete_raw_text
    fwrite(tweetData, file=outFile, sep="\t", quote=F)
    system(paste("gzip -f", outFile))
}    



# inFile: a tsv.gz (or similar) containing columns tweet_id, tweet_text, shortened_url, canonical_url, retweet_prefix, quote_of_user_name, and quoted_text.
#   Repeats same tweet on multiple rows, once per URL. May include tweets w/o URLs. (Doesn't matter if it has only "external" URLs or also twitter_* ones.)
# outFile: a tsv file with same fields as inFile + classifier_score. See classifierThreshold for which lines.
#   If classifierThreshold is NULL (implied if saveDebuggingColumnsRows is TRUE), keeps all rows and returns additional columns. 
#   (File will have '.gz' appended to argument provided.)
# keywordFile: used to define the training set, one term (word or phrase) per line. If a tweet contains one of these terms, it's ALWAYS kept (so, 
#   be sure to put only high-precision terms in this file.)
# modelFileOutStem: if non-NULL, we'll save two .rds files beginning with this path + prefix, to allow using same model (including doc->term mapping) on future tweets
#   (plus a 3rd file == a plot of training set scores)
# classifierThreshold: Normally, keep rows with scores above this value. If it's NULL or if saveDebuggingColumnsRows=T, then keep all rows.
# saveDebuggingColumnsRows: flag for printing larger outfile to inspect scores.
# repeatableMode: flag to set random seed
# returnAsTweets: return one line (max) per tweet, not per URL
filterURLDataUsingClassifier = function(inFile, outFile, keywordFile, modelFileOutStem=NULL, classifierThreshold=.8, saveDebuggingColumnsRows=FALSE,
                                        goFastUseNaiveBayes=F, noTraining=F, loadVectorizer=F, 
                                        repeatableMode = F, returnAsTweets = F) {
    
    if (repeatableMode) {
        set.seed(1)
    }
    
    startTime = Sys.time()
    print(paste("Run started at", startTime))
    
    # 1. Read data, change to tweet level (from tweet-url level).
    inData = fread(paste("gzcat", inFile), sep = "\t", quote="'")
    tweetData = constructTweets(inData)    # contains tweet_id, complete_raw_text
    print(paste("Done constructing tweets at", Sys.time() - startTime))

    # 2. All the text processing and classification work! Match against whitelist, tokenize text, build DocumentTermMatrix, 
    # construct training set, train classifier, get predictions from classifier.
    tweetData = classifyTweets(keywordFile, tweetData = tweetData[, .(tweet_id, complete_raw_text)],  modelFileOutStem, startTime, goFastUseNaiveBayes, 
                                noTraining=noTraining, loadVectorizer=loadVectorizer)
    
    # 3. Change back to tweet-url level, apply threshold for filtering, save
    dataWithScores = merge(inData, tweetData, by="tweet_id")
    
    debuggingColNames = c("classifier_label", "complete_raw_text", "rest_of_text", "raw_classifier_score", "white_terms")
    if (returnAsTweets) {
        # simplify dataWithScores quite a lot
        
        tweetColsToKeep = c("tweet_id", "user_id", "screen_name", "tweet_date", "complete_raw_text", "classifier_score")
        if (saveDebuggingColumnsRows) {
            tweetColsToKeep = union(tweetColsToKeep, debuggingColNames)
        }
        
        tweetColsToKeep = intersect(colnames(dataWithScores), tweetColsToKeep)
        # n.b. If we're in this clause, don't count "complete_raw_text" as a debugging col later.
        debuggingColNames = setdiff(debuggingColNames, c("complete_raw_text"))
        
        dataWithScores = dataWithScores[!duplicated(tweet_id), tweetColsToKeep, with=F]
        print(paste("Saving as", nrow(dataWithScores), "distinct tweets"))
    }
    
    colsWanted = colnames(dataWithScores)
    if (saveDebuggingColumnsRows) {
        classifierThreshold = NULL
    } else {
        # toss debugging cols; only keep classifier_score
        colsWanted = setdiff(colsWanted, debuggingColNames)
    }
    if (! is.null(classifierThreshold)) {
        print(paste("Keeping the", sum(dataWithScores$classifier_score >= classifierThreshold), "of", nrow(dataWithScores), 
                    "lines with a classifier score >=", classifierThreshold))
        dataWithScores = dataWithScores[classifier_score >= classifierThreshold,]
    }
    dataWithScores = dataWithScores[, colsWanted, with=F]
    
 
    fwrite(dataWithScores, file=outFile, sep="\t", quote=F)
    system(paste("gzip -f", outFile))
    
}



# Gathers text + URLs for each tweet
# inData: a data.table (straight from the inFile)
# returns: a data.table with columns tweet_id and complete_raw_text 
constructTweets = function(inData) {
    setkey(inData, tweet_id)
    
    # Replace shortened URLs with expanded ones. 
    substituted = inData[, `:=`(updated_tweet_text = mgsub(tweet_text, shortened_url, canonical_url), 
                                updated_quoted_text =  mgsub(quoted_text, shortened_url, canonical_url)), by=tweet_id]
    onePerTweet = substituted[!duplicated(tweet_id),]
    onePerTweet[, quoting := ifelse(quote_of_user_name == "", "", paste0("[QTG @", quote_of_user_name, "]"))]
    
    # The whole reason we expanded URLs is because the t.co versions are meaningless. Delete remaining ones,
    # or anyway (more cautiously) the ones I expect to exist: from tweet_text to the quoted_status.
    # Remove the final t.co from updated_tweet_text, and only if there's a quote
    onePerTweet[quote_of_user_name != '', updated_tweet_text := sub("(?<!\\w)https?\\://t\\.co/\\S+\\s*$", "", updated_tweet_text, perl=T)]
    
    # text: Paste back together the RT prefix, the tweet_text, the quoting marker, and the quoted_text
    onePerTweet = onePerTweet[, .(tweet_id, complete_raw_text = paste(retweet_prefix, updated_tweet_text, 
                                                                      quoting, updated_quoted_text))]
    return(onePerTweet[, .(tweet_id, complete_raw_text)])
}

# helper for constructTweets
mgsub <- function(txt, patterns, reps, fixed = T, ...) {
    txt1 = txt[1]
    sapply(seq_len(length(patterns)), function(i) {
        if (patterns[i] != '' && reps[i] != '') {
            txt1 <<- gsub(patterns[i], reps[i], txt1, fixed = fixed, ...)
        } else {
            txt1
        }})
    return(txt1)
}
