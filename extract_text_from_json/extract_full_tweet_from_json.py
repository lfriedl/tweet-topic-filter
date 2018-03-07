import sys
import unicodecsv as csv
import ujson as json
import gzip
import tweetURLData 
import datetime


# These settings create a tab-separated file with at least one line per tweet, and additional lines if it contains additional URLs.
# With these defaults, output contains every tweet and every URL expansion. 
# See arguments to tweetURLData.extract_urls_from_tweet() for ways to filter the output.


if len(sys.argv) < 3:
        print "Usage: extract_full_tweet_from_json.py <inFile.json.gz> <outFile.tsv.gz>"
        sys.exit(1)

input_path = sys.argv[1]
output_path = sys.argv[2]


with gzip.open(input_path, 'r') as fin, gzip.open(output_path, 'wb') as fout:
    wrtr = csv.DictWriter(fout, tweetURLData.URL_FIELDS,
                          delimiter='\t', quotechar="'")
    wrtr.writeheader()

    for line in fin:
        tweet = json.loads(line.decode("utf8"))
        map(wrtr.writerow, tweetURLData.extract_urls_from_tweet(tweet, include_non_url_tweets = True, show_internal_twitter = True))

        # example syntax using a date filter
        #row_data = tweetURLData.extract_urls_from_tweet(tweet, earliest_date = datetime.date(2016, 5, 1), latest_date = datetime.date(2016, 11, 30),
        #                                                        show_internal_twitter=True, include_non_url_tweets = True)
        #if len(row_data) != 0:
        #    map(wrtr.writerow, row_data)


