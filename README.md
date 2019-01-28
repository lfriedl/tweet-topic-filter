# tweet-topic-filter
A classifier to detect political (or another topic of) tweets.

Uses a topic-specific whitelist to identify a set of positives, then trains a classifier to detect additional tweets in the topic. Outputs a [0, 1] score per tweet.

The whitelist included here (under `keyword_data/`) was developed for the topic of "political tweets related to the 2016 U.S. election." 

To adapt the classifier for a different topic, you will need to provide a new whitelist. It's important that the whitelist be high precision; that is, any tweet matching the whitelist is automatically classified as positive, 
so check carefully and remove any whitelist terms that create false positives. 

(N.B. Since this approach relies on a manually curated whitelist, it's not easily extensible to new topics.
But it's a perfectly reasonable "quick and dirty" solution for a single topic.)


In this repo:

 * `gather_example_data/` shows how to collect some JSON data to put into the `example_data/` directory.
 * Code in `extract_text_from_json/` converts the JSON data to a tab-delimited format. It pulls out info about URLs and retweets.  Each row of the output represents either one tweet or one URL (= when the tweet contains more than one URL).
 * The `filter_tweets/` directory contains code that takes the tab-delimited format, converts it to 1 row per tweet, runs the classifier, and saves output in the same tab-delimited format as above.
   * `politicalFilterURLData.R`: the wrapper that converts from/to tab-delimited format.
   * `classifyTweets.R`: the classifier at the heart of this repo. As input, expects a table with a column called 'complete_raw_text'.
   * `textProcessingForClassifier.R`: the low-level text processing for matching whitelist terms, tokenizing text (including hashtags and URLs), etc.

