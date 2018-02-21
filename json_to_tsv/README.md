Code and scraps for extracting as much text as possible from the JSON of a tweet status object. 


What you need to run:

* `extract_full_tweet_from_json.py`: Wrapper that takes a JSON file and outputs a tab-separated file with many fields. The TSV contains one line per URL, not per tweet.

[Current status: code refactored for this repo, not yet tested or all integrated. TODO:
 
* Change default to write a line for every tweet, even those w/o URLs
* Make it possible to call stuff in expandURLs as part of everything else
]

Other code:

* `tweetData.py`: Python module that grabs metadata from a JSON object. It descends any retweeted and quoted tweets to pull out the non-truncated text, the quoted text, and handles and usernames of people quoted, retweeted, etc.
* `tweetURLData.py`: Python module for replacing (displayed) `t.co` links with the 'expanded_url' present in the JSON.
* `expandURLs.py`: Python module for going a step beyond the 'expanded_url' field. Uses the internet to actually hit the URl, following all redirects, and grabs the title and other fields from the HTML page.