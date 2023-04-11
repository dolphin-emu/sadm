#! /usr/bin/env python3

import hashlib
import hmac
import os
import requests

CALLBACK_URL = 'https://dolphin-emu.org/download/new/'
DOWNLOADS_CREATE_KEY = open(os.environ['DOWNLOADS_CREATE_KEY_PATH'], 'rb').read().strip()

if __name__ == '__main__':
    branch = os.environ['BRANCH']
    shortrev = os.environ['SHORTREV']
    hash = os.environ['HASH']
    author = os.environ['AUTHOR']
    description = os.environ['DESCRIPTION']
    target_system = os.environ['TARGET_SYSTEM']
    build_url = os.environ['BUILD_URL']
    user_os_matcher = os.environ['USER_OS_MATCHER']

    msg = u"%d|%d|%d|%d|%d|%d|%d|%d|%s|%s|%s|%s|%s|%s|%s|%s" % (
        len(branch), len(shortrev), len(hash), len(author), len(description),
        len(target_system), len(build_url), len(user_os_matcher),

        branch, shortrev, hash, author, description, target_system, build_url,
        user_os_matcher
    )
    hm = hmac.new(DOWNLOADS_CREATE_KEY, msg.encode("utf-8"), hashlib.sha1)

    post_data = {
        'branch': branch,
        'shortrev': shortrev,
        'hash': hash,
        'author': author,
        'description': description,
        'target_system': target_system,
        'build_url': build_url,
        'user_os_matcher': user_os_matcher,
        'hmac': hm.hexdigest()
    }

    r = requests.post(CALLBACK_URL, data=post_data)
    print(r.text)
