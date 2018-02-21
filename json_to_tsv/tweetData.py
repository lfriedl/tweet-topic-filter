
import re

# Pull out non-URL data about tweet. Returns a dictionary (filling in the fields listed just below).
def extract_tweet_info(json):
    data = {'user_id': json['user']['id_str'],
            'tweet_id': json['id_str'],
            'tweet_date': json['created_at'],
            'tweet_text': '',
            'retweet_prefix': '',
            'quoted_text': '',
            'retweet_of_tweet_id': '',
            'retweet_of_user_id': '',
            'quote_of_tweet_id': '',
            'quote_of_user_id': '',
            'quote_of_user_name': '',
            'reply_to_tweet_id': '',
            'reply_to_user_id': ''
            }

    is_retweet = json.has_key('retweeted_status')
    is_reply = (json.has_key('in_reply_to_status_id_str') and json['in_reply_to_status_id_str'] is not None) or \
               (json.has_key('in_reply_to_user_id_str') and json['in_reply_to_user_id_str'] is not None)
    is_quote = json['is_quote_status']

    data['tweet_text'] = get_text_field(json)

    if is_retweet:   # grab original (non-truncated) text, plus save the "RT @username: " prefix
        data['retweet_prefix'] = 'RT @' + json['retweeted_status']['user']['screen_name'] + ": "
        data['tweet_text'] = get_text_field(json['retweeted_status'])
        data['retweet_of_tweet_id'] = json['retweeted_status']['id_str']
        data['retweet_of_user_id'] = json['retweeted_status']['user']['id_str']

    if is_reply:
        if json.has_key('in_reply_to_status_id_str') and json['in_reply_to_status_id_str'] is not None:
            data['reply_to_tweet_id'] = json['in_reply_to_status_id_str']
        if json.has_key('in_reply_to_user_id_str') and json['in_reply_to_user_id_str'] is not None:
            data['reply_to_user_id'] = json['in_reply_to_user_id_str']

    if is_quote:
        # quoted_status stuff may be missing, e.g. if initial status has been deleted
        if json.has_key('quoted_status_id_str'):
            data['quote_of_tweet_id'] = json['quoted_status_id_str']

        # go get the text being quoted and user

        if is_retweet and json['retweeted_status'].has_key('quoted_status'):
            data['quote_of_user_id'] = json['retweeted_status']['quoted_status']['user']['id_str']
            data['quote_of_user_name'] = json['retweeted_status']['quoted_status']['user']['screen_name']
            data['quoted_text'] = get_text_field(json['retweeted_status']['quoted_status'])
        else:
            if json.has_key('quoted_status'):
                data['quote_of_user_id'] = json['quoted_status']['user']['id_str']
                data['quote_of_user_name'] = json['quoted_status']['user']['screen_name']
                data['quoted_text'] = get_text_field(json['quoted_status'])

    del data['quote_of_user_id']   # not currently wanted in output (but needed it to check for interaction)

    return data

# gets top-level text field from the json element passed in, either 'full_text' (optionally dipping into extended_tweet) or 'text'
bad_chars = re.compile('[\r\n\t]+')
def get_text_field(json):
    txt = ''
    if 'full_text' in json:
        txt = json['full_text']
    elif 'extended_tweet' in json and 'full_text' in json['extended_tweet']:
        txt = json['extended_tweet']['full_text']
    else:
        txt = json.get('text', '')
    return bad_chars.sub(' ', txt)

