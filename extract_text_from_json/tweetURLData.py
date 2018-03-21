import re
import datetime
from tweetData import extract_tweet_info

# This module pulls out the URLs in tweets.
# Describes them by (1) what they point to = link_type
#                       among {external (anything but twitter), twitter_status, twitter_media}
#                   (2) where in the tweet they are = where_url_found
#                        among {orig, retweeted, quoted}
#                   (3) which user we saw them from = who_url_from

# logic for traversing the json:
# If tweet is original or reply, collect URLs and media. -> where_url_found="orig"
# If tweet is retweet, use the retweeted_status (instead) to get (non-truncated) URLs and media. -> where_url_found="retweeted"
# If it's a quote, descend the quote to add its URLs. -> where_url_found="quoted"
# If it's a RT of a quote, handle links from both levels. Those from the (inner) quote get labeled just "quoted."
# (We don't look for further nesting, e.g., quotes of quotes.)

# json tips: -always use extended_tweet (also within retweeted_status or quoted_status) when available, since it has less truncation.
#            -extended_entities doesn't offer anything new.


# fields we'll print -- ok if it's a superset of fields returned in dictionary, but python gives error if dictionary has extras
URL_FIELDS = ['tweet_id', 'user_id', 'screen_name', 'tweet_date', 'retweet_prefix', 'tweet_text',
              'quoted_text', 'retweet_of_tweet_id', 'retweet_of_user_id',
              'quote_of_tweet_id', 'quote_of_user_name', 'reply_to_tweet_id',
              'where_url_found',  'link_type', 'who_url_from',
              'shortened_url', 'canonical_url', 'website']

oldFormat = False
if oldFormat:
    URL_FIELDS = ['tweet_id', 'user_id', 'screen_name', 'tweet_date', 'retweet_prefix', 'tweet_text',
                  'quoted_text', 'retweet_of_tweet_id', 'retweet_of_user_id',
                  'quote_of_tweet_id', 'quote_of_user_name', 'reply_to_tweet_id',
                  'candidate_interaction', 'where_url_found', 'who_url_from',
                  'link_type', 'shortened_url', 'canonical_url', 'website', 'title',
                  'date_published', 'description', 'author']

TWEET_URL_PATTERN = re.compile('.*twitter\.com/(.*)/status/(\d+)($|/.*)$')
URL_PATTERN = re.compile('https?://([^/]+)')


# extract_urls_from_tweet optional arguments:
#   earliest_date, latest_date -- date objects
#   include_non_url_tweets -- True means print a line for each tweet even if it has no URLs
#   show_internal_twitter -- True means print lines even for URLs that point to Twitter (will have link_type: twitter_status or twitter_media);
#                the default, False, only prints lines for external (non-Twitter) URLs.
def extract_urls_from_tweet(t, earliest_date=None, latest_date=None,
                            show_internal_twitter=False,
                            include_non_url_tweets=False):

    python_tweet_date = datetime.datetime.strptime(
        t["created_at"], "%a %b %d %H:%M:%S +0000 %Y").date()
    if earliest_date and python_tweet_date < earliest_date:
        return {}
    if latest_date and python_tweet_date > latest_date:
        return {}

    ##############################################

    # Get non-URL fields
    tweet_info = extract_tweet_info(t)
    if 'reply_to_user_id' in tweet_info:
        del tweet_info['reply_to_user_id']

    rt = t.get('retweeted_status', None)
    quote = t.get('quoted_status', None)
    if quote is None and rt is not None:
        quote = rt.get('quoted_status', None)

    # Get URLs (and media) from { original tweet or retweeted status } and quoted status. (But we'll drop media below.)
    orig_ents = get_ext_status_ents(t)
    rt_ents = get_ext_status_ents(rt)
    quoted_ents = get_ext_status_ents(quote)

    if rt is None:
        urls = [('orig', False, url, '') for url in orig_ents.get('urls', [])] + \
            [('orig', True, url, '') for url in orig_ents.get('media', [])]
    else:
        urls = [('retweeted', False, url, rt['user']['screen_name']) for url in rt_ents.get('urls', [])] + \
            [('retweeted', True, url, rt['user']['screen_name']) for url in rt_ents.get('media', [])]
    urls = urls + \
        [('quoted', False, url, quote['user']['screen_name']) for url in quoted_ents.get('urls', [])] + \
        [('quoted', True, url, quote['user']['screen_name']) for url in quoted_ents.get('media', [])]

    # Get IDs of tweet and quoted tweet (we'll skip any links back to these)
    self_and_quoted_ids = [t.get('id_str', '')]
    if quote is not None:
        self_and_quoted_ids.append(quote['id_str'])

    res = []  # all the urls for this tweet
    for url_type, is_media, url_struct, url_orig in urls:
        expanded_url = url_struct.get('expanded_url', None)
        if expanded_url is None or not isinstance(expanded_url, basestring):
            continue

        rec = tweet_info.copy()  # this url
        m = TWEET_URL_PATTERN.match(expanded_url)        # twitter url parts

        if m is None:
            # simplest case: external URL
            link_type = 'external'
            domain_match = URL_PATTERN.match(expanded_url)
            rec.update({
                'where_url_found': url_type,
                'who_url_from': url_orig,
                'link_type': link_type,
                'shortened_url': url_struct['url'],
                'canonical_url': expanded_url,
                'website': domain_match.group(1) if domain_match is not None else None
            })
        else:
            # this is a twitter url
            # url shows the owner and status id, but it's media if there's extra stuff after the status id
            tweeted_status_owner, tweeted_status_id, tweeted_status_extra = m.groups()
            is_tweeted_status = (tweeted_status_extra == '' or tweeted_status_extra == '/')

            # use it only if we want twitter urls and this isn't just a link to the status being quoted
            # nor to the original. (The latter has been seen when user posts their own media but, lacking extended_tweet, the 
            # url only shows a self-loop.)
            if not show_internal_twitter or (is_tweeted_status and not is_media and
                                         tweeted_status_id in self_and_quoted_ids and
                                         (url_type == 'orig' or url_type == 'retweeted')):
                continue

            rec.update({
                'where_url_found': url_type,
                'who_url_from': url_orig,
                'link_type': 'twitter_status' if is_tweeted_status else 'twitter_media',
                'shortened_url': url_struct['url'],
                'canonical_url': expanded_url,
                'website': 'twitter.com'
            })
            if oldFormat:
                rec['author'] = tweeted_status_owner if tweeted_status_owner != 'i / web' else ''

        res.append({k : strip_newlines(v) for k,v in rec.items()})

    if not len(res) and include_non_url_tweets:
        res.append({k : strip_newlines(v) for k,v in tweet_info.items()})
        
    return res


def strip_newlines(x):
    return (unicode(x).replace(u"\r\n",u"   ")
                      .replace(u"\r",u"   ")
                      .replace(u"\n",u"   ")
                      .replace(u"\t", u"   ")
                      .replace(u"\"", u"'"))
            
def get_ext_status_ents(status):
    if status is None:
        return {}
    return status['extended_tweet']['entities'] if 'extended_tweet' in status \
        else status['entities']


