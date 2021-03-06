Code and scraps for extracting as much text as possible from the JSON of a tweet status object. 

Uses "extended" tweet fields ('full_text', 'extended_tweet') when they're present. They're generally needed in order for the JSON to contain full info.
Getting them might require setting the option "tweet_mode=extended" in the query to Twitter.


What you need to run:

* `extract_full_tweet_from_json.py`: Wrapper that takes a JSON file and outputs a tab-separated file with many fields. The TSV contains one line per URL, not per tweet.


Other code:

* `tweetData.py`: Python module that grabs metadata from a JSON object. It descends any retweeted and quoted tweets to pull out the non-truncated text, the quoted text, and handles and usernames of people quoted, retweeted, etc.
* `tweetURLData.py`: Python module for replacing (displayed) `t.co` links with the 'expanded_url' present in the JSON.
* `expandURLs.py`: Python module for going a step beyond the 'expanded_url' field. Uses the internet to actually hit the URl, following all redirects, and grabs the title and other fields from the HTML page. (Not currently called.)


[TODO:
 
* Integrate expandURLs; make it possible to call fetch_html() and parse_page() as part of everything else. (note to self: see retryBrokenLinks.py and pullAllURLs.py from old repo for examples)
* Check and handle: if you quote someone who posts a video (e.g.), does the link to it show up twice in the tweet?
]
