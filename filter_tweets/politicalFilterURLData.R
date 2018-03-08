source("classifyTweets.R")
library(bit64)

# Wrapper for calling classifyTweets on URL data.
# Builds 1 model per input file. Assumes input file fits in memory.
# Work of the wrapper: 
# -Changes data rows from tweet-URLs to tweets (for classification) and back again.
# -Constructs tweet text "complete_raw_text" from input columns (includes RT, quoted handles and expanded URLs).


# inFile: a tsv.gz (or similar) containing columns tweet_id, tweet_text (and retweet_prefix, quote_of_user_name and quoted_text) and canonical_url.
#   Repeats same tweet on multiple rows (assumed to be sequential!), once per URL. (Doesn't matter if it has only "external" URLs or also twitter_* ones.)
# outFile: a tsv file with same fields as inFile + political_classifier_score. See classifierThreshold for which lines.
#   If classifierThreshold is NULL (implied if saveDebuggingColumnsRows is TRUE), keeps all rows and returns additional columns. 
#   (File will have '.gz' appended to argument provided.)
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
    
    colsWanted = colnames(dataWithScores)
    if (saveDebuggingColumnsRows) {
        classifierThreshold = NULL
    } else {
        # all we add to original is political_classifier_score
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


# Gathers text + URLs for each tweet
# inData: a data.table (straight from the inFile)
# returns: a data.table with columns tweet_id and complete_raw_text 
constructTweets = function(inData, newWay=T) {
    setkey(inData, tweet_id)
    
    # Replace shortened URLs with expanded ones. 
    if (newWay) {
        require("stringr")
    
        tweetData = inData[canonical_url != '', tweet_text:=str_replace(tweet_text, fixed(shortened_url), canonical_url)]
        tweetData = tweetData[canonical_url != '', quoted_text:=str_replace(quoted_text, fixed(shortened_url), canonical_url)]
        
    firstRowEachTweet = !duplicated(tweetData$tweet_id)
        firstRowEachTweet = !duplicated(tweetData$tweet_id)
        tweetData$quoting = ifelse(tweetData$quote_of_user_name == '', '', paste0("[QTG @", tweetData$quote_of_user_name, "]"))
        
        tweetData = tweetData[firstRowEachTweet, .(tweet_id, complete_raw_text = paste(retweet_prefix, tweet_text, 
                                                                              quoting, quoted_text))]
        return(tweetData)
    } else if (T) {
        swapIn = function(text, from, to) {
            if (!is.null(to[[1]]) && !is.null(from[[1]]) && length(to) > 0 && length(from) > 0
                && to[[1]] != '' && from[[1]] != '') {
                namedVector = unlist(to)
                names(namedVector) = unlist(from)
                return(str_replace_all(text, namedVector))
            } else {
                return(text)
            }
        }
        tweetURLs_orig = inData[where_url_found != 'quoted', 
                              .(orig_shortened = list(.SD[, shortened_url]), orig_canon = list(.SD[, canonical_url])),
                              by = tweet_id, .SDcols=c("shortened_url", "canonical_url")]
        tweetURLs_quoted = inData[where_url_found == 'quoted', 
                                  .(quoted_shortened = list(.SD[, shortened_url]), quoted_canon = list(.SD[, canonical_url])),
                                  by = tweet_id, .SDcols=c("shortened_url", "canonical_url")]
        tweetData = merge(inData, tweetURLs_orig, all.x=T)  
        tweetData = merge(tweetData, tweetURLs_quoted, all.x=T) 
        # merges produce NULLs, but they're inside lists. Handle them during swapIn().
        # that produced NAs. Change to empty strings.
        #tweetData[is.null(orig_shortened[[1]]), `:=`(orig_shortened = list(""), orig_canon = list(""))]
        #tweetData[is.null(quoted_shortened[[1]]), `:=`(quoted_shortened = list(""), quoted_canon = list("")) ]  # these give warnings but seem to work
        
        
        onePerTweet = tweetData[!duplicated(tweet_id),]
        onePerTweet[, updated_tweet_text := mapply(swapIn, tweet_text, orig_shortened, orig_canon)]
        onePerTweet[, updated_quoted_text := mapply(swapIn, quoted_text, quoted_shortened, quoted_canon)]
        
        onePerTweet[, quoting := ifelse(quote_of_user_name == "", "", paste0("[QTG @", quote_of_user_name, "]"))]
        # text: Paste back together the RT prefix, the tweet_text, the quoting marker, and the quoted_text
        onePerTweet = onePerTweet[, .(tweet_id, raw_text = paste(retweet_prefix, updated_tweet_text, 
                                                                              quoting, updated_quoted_text))]
        # The whole reason we expanded URLs is because the t.co versions are meaningless. Delete those.
        onePerTweet[, complete_raw_text := gsub("(?<!\\w)https?\\://t\\.co/\\S+", "", raw_text, perl=T)]
        
        return(onePerTweet[, .(tweet_id, complete_raw_text)])
        
        
    } else {  # old way
    
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
    
    
}

