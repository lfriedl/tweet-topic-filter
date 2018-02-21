# tweet-topic-filter
A classifier for political (or another topic of) tweets. Starts from tweets in JSON form (or, barring that, as strings). Uses a whitelist to identify a set of positives, then trains a classifier to detect additional tweets in the topic. Outputs a [0, 1] score per tweet.

Work in progress. Use at your own risk.