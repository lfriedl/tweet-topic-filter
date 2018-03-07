import re
import datetime
from tweetData import extract_tweet_info

TWEET_URL_PATTERN = re.compile('.*twitter\.com/(.*)/status/(\d+)($|/.*)$')
URL_PATTERN = re.compile('https?://([^/]+)')


URL_FIELDS = ['tweet_id', 'user_id', 'screen_name', 'tweet_date', 'retweet_prefix', 'tweet_text',
              'quoted_text', 'retweet_of_tweet_id', 'retweet_of_user_id',
              'quote_of_tweet_id', 'quote_of_user_name', 'reply_to_tweet_id',
              'candidate_interaction', 'where_url_found', 'who_url_from',
              'link_type', 'shortened_url', 'canonical_url', 'website', 'title',
              'date_published', 'description', 'author']

# extract_urls_from_tweet optional arguments:
# 	earliest_date, latest_date -- date objects
#	include_non_url_tweets -- True means print a line for each tweet even if it has no URLs
# 	show_internal_twitter -- True means print lines even for URLs that point to Twitter (will have link_type: twitter_status or twitter_media);
# 				 the default, False, only prints lines for external (non-Twitter) URLs.
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

    # Get URLs (and media) from { original tweet or retweeted status } and quoted status. (But we'll drop media below.)
    rt = t.get('retweeted_status', None)
    quote = t.get('quoted_status', None)

    orig_ents = get_ext_status_ents(t)
    rt_ents = get_ext_status_ents(rt)
    quoted_ents = get_ext_status_ents(quote)

    if rt is None:
        urls = [('orig', False, url) for url in orig_ents.get('urls', [])] + \
            [('orig', True, url) for url in orig_ents.get('media', [])]
    else:
        urls = [('retweeted', False, url) for url in rt_ents.get('urls', [])] + \
            [('retweeted', True, url) for url in rt_ents.get('media', [])]
    urls = urls + \
        [('quoted', False, url) for url in quoted_ents.get('urls', [])] + \
        [('quoted', True, url) for url in quoted_ents.get('media', [])]

    # Get IDs of tweet and quoted tweet (we'll skip any links back to these)
    tid = t.get('id_str', '')
    self_and_quoted_ids = [tid, quote['id_str']
                           ] if quote is not None else [tid]

    res = []
    for url_type, is_media, url_struct in urls:
        expanded_url = url_struct.get('expanded_url', None)
        if expanded_url is None or not isinstance(expanded_url, basestring):
            continue

        # twitter url parts
        m = TWEET_URL_PATTERN.match(expanded_url)
        rec = tweet_info.copy()
        if 'reply_to_user_id' in rec:
            del rec['reply_to_user_id']
        url_orig = next((x['user']['screen_name']
                        for x in [rt, quote] if x is not None), '')
        
        if m is not None:  # this is a twitter url
            # url shows the owner and status id, but it's media if there's extra stuff after the status id
            tweeted_status_owner, tweeted_status_id, tweeted_status_ext = m.groups()
            is_tweeted_status = (tweeted_status_ext == '' or tweeted_status_ext == '/')

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
                'website': 'twitter.com',
                'author': tweeted_status_owner if tweeted_status_owner != 'i/web' else ''
            })
        else:
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
            
        res.append({k : strip_newlines(v) for k,v in rec.items()})

    if not len(res) and include_non_url_tweets:
        if 'reply_to_user_id' in tweet_info:
            del tweet_info['reply_to_user_id']
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


