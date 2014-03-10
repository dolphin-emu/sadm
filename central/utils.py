"""Utility functions and classes."""

import json
import requests
import threading


def shorten_url(url):
    """Minify a URL using goo.gl."""
    headers = {'Content-Type': 'application/json'}
    data = {'longUrl': url}
    return requests.post('https://www.googleapis.com/urlshortener/v1/url',
                         headers=headers, data=json.dumps(data)).json()['id']


class DaemonThread(threading.Thread):
    daemon = True


class ObjectLike:
    """Transforms a dict-like structure into an object-like structure."""

    def __init__(self, dictlike):
        self.reset(dictlike)

    def reset(self, dictlike):
        self.dictlike = dictlike

    def __getattr__(self, name):
        val = self.dictlike.get(name)
        if isinstance(val, dict):
            return ObjectLike(val)
        else:
            return val

    def __str__(self):
        return str(self.dictlike)

    def __repr__(self):
        return repr(self.dictlike)
