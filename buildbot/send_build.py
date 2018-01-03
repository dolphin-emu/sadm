#! /usr/bin/env python2

import hashlib
import hmac
import os
import requests

CALLBACK_URL = 'https://dolphin-emu.org/download/new/'
DOWNLOADS_CREATE_KEY = open('/etc/dolphin-keys/downloads-create').read().strip()

def get_env_var(name):
    if name not in os.environ:
        raise KeyError("%s is missing from the environment" % name)
    return os.environ[name].decode("utf-8")

if __name__ == '__main__':
    branch = get_env_var('BRANCH')
    shortrev = get_env_var('SHORTREV')
    hash = get_env_var('HASH')
    author = get_env_var('AUTHOR')
    description = get_env_var('DESCRIPTION')
    target_system = get_env_var('TARGET_SYSTEM')
    build_url = get_env_var('BUILD_URL')
    user_os_matcher = get_env_var('USER_OS_MATCHER')

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
    print r.text
