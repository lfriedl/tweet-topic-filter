The classifier code expects, as input, a single (compressed) JSON file of tweets.

## Example data (celebrities)

I can't share the Twitter data I normally work with, so I constructed an example data set by crawling the current timelines of 9 popular accounts. Technically I shouldn't share this either, but I can provide the code I used to construct it.

* `gather_sample_data.py` takes the most recent 3200 tweets from each of 9 celebrities and stores them as raw JSON files, one per person, in a subdirectory called `sampleAccts`. 
	* To use it, you'll need to set up your own authentication tokens with the Twitter API. See, e.g., <http://tweepy.readthedocs.io/en/v3.5.0/auth_tutorial.html>.
	* Once that's set up, replace `twitterAuthLDF` in the code with your new version.
	* At the command line: `mkdir sampleAccts`
	* Run `python gather_sample_data.py`
	* `cat sampleAccts/* > celebrities.json`
	* `gzip celebrities.json`
	
* Alternative route to gathering data: <http://www.docnow.io/catalog/> has Twitter data sets, which, as per Twitter's terms of service, provide only tweet IDs. The page outlines how to go about "hydrating" them into JSON files.