#! /usr/bin/env python2

import hashlib
import hmac
import os
import requests

CALLBACK_URL = 'http://dolphin-emu.org/download/new/'
DOWNLOADS_CREATE_KEY = 'password'

def get_env_var(name):
    if name not in os.environ:
        raise KeyError("%s is missing from the environment" % name)
    return os.environ[name]

if __name__ == '__main__':
    branch = get_env_var('BRANCH')
    shortrev = get_env_var('SHORTREV')
    hash = get_env_var('HASH')
    author = get_env_var('AUTHOR')
    description = get_env_var('DESCRIPTION')
    build_type = get_env_var('BUILD_TYPE')
    build_url = get_env_var('BUILD_URL')

    msg = "%d|%d|%d|%d|%d|%d|%d|%s|%s|%s|%s|%s|%s|%s" % (
        len(branch), len(shortrev), len(hash), len(author), len(description),
        len(build_type), len(build_url),

        branch, shortrev, hash, author, description, build_type, build_url
    )
    hm = hmac.new(DOWNLOADS_CREATE_KEY, msg, hashlib.sha1)

    post_data = {
        'branch': branch,
        'shortrev': shortrev,
        'hash': hash,
        'author': author,
        'description': description,
        'build_type': build_type,
        'build_url': build_url,
        'hmac': hm.hexdigest()
    }

    r = requests.post(CALLBACK_URL, data=post_data)
    print r.text
