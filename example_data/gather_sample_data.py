import codecs
import tweepy
import sys
import twitterAuthLDF
import ujson as json


# Quick program that uses Twitter API to grab timelines for a list of users and store them as json files.
# To use: you must replace 'twitterAuthLDF.getAPIobj()' with a call that authenticates your account.

def main():
    outputPath = './sampleAccts/'

    APIobj = twitterAuthLDF.getAPIobj()

    # Some celebrity handles
    acctsToGrab = ['katyperry', 'rihanna', 'TheEllenShow', 'jtimberlake', 'ArianaGrande', 'selenagomez', 'ddlovato', 'jimmyfallon', 'cnnbrk']
    
    for user in acctsToGrab:
       grabTimeline(user, APIobj, outputPath)



# Tweepy takes care of pagination. If you want all the items available, regardless of how many pages they're spread out over, write:
# for <x> in tweepy.Cursor(<function>, <args>).items():
#
# To automatically wait (15 min) when rate limit is reached, use:
# for <x> in limit_handled(tweepy.Cursor(<function>, <args>).items()):


def limit_handled(cursor):
    while True:
        try:
            yield cursor.next()
        except tweepy.RateLimitError:
            sys.stderr.write("(Rate limit -- waiting 15 min)\n")
            time.sleep(15 * 60)
        # if you get a Twitter error in the middle of iterating, consider that the end of the list, but keep going
        except tweepy.TweepError:
            sys.stderr.write("Got Twitter error, skipping rest of list\n")
            break

def grabTimeline(userOfInterest, api, path):
    outfile = path + userOfInterest + '.json'

    print "Getting timeline for " + userOfInterest
    with codecs.open(outfile, 'w', encoding='utf-8') as fout:

        # "count" arg: set to max allowed per call. "Cursor.items()" will call it as many times as possible.
        for tweet in limit_handled(tweepy.Cursor(api.user_timeline, screen_name=userOfInterest, count=200, tweet_mode='extended').items()):
            fout.write(json.dumps(tweet._json) + u'\n')


if __name__ == "__main__":
    main()
