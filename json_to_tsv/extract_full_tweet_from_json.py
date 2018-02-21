import sys
import unicodecsv as csv
import ujson as json
import gzip
import tweetURLData 


if len(sys.argv) < 3:
        print "Usage: extract_full_tweet_from_json.py <inFile.json.gz> <outFile.tsv.gz>"
        sys.exit(1)

input_path = sys.argv[1]
output_path = sys.argv[2]


with gzip.open(input_path, 'r') as fin, gzip.open(output_path, 'wb') as fout:
    wrtr = csv.DictWriter(fout, tuu.URL_FIELDS,
			  delimiter='\t', quotechar="'")
    wrtr.writeheader()

    for line in fin:
	tweet = json.loads(line.decode("utf8"))
	map(wrtr.writerow, tweetURLData.extract_urls_from_tweet(tweet))


