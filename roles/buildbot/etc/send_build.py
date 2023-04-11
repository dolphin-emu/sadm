#! /usr/bin/env python3

import argparse
import hashlib
import hmac
import os
import requests

CALLBACK_URL = 'https://dolphin-emu.org/download/new/'
DOWNLOADS_CREATE_KEY = open(os.environ['DOWNLOADS_CREATE_KEY_PATH'], 'rb').read().strip()

if __name__ == '__main__':
    parser = argparse.ArgumentParser(
        description='Signals to the website that a new build is available.')
    parser.add_argument(
        '--branch', required=True, help='Git branch for this build')
    parser.add_argument(
        '--shortrev', required=True, help='Short rev name for this build')
    parser.add_argument(
        '--hash', required=True, help='Full Git commit hash for this build')
    parser.add_argument(
        '--author', required=True, help='Name of the author for this build')
    parser.add_argument(
        '--description', required=True, help='Git commit message for this build')
    parser.add_argument(
        '--target_system', required=True, help='Target system string')
    parser.add_argument(
        '--build_url', required=True, help='URL at which the build can be found')
    parser.add_argument(
        '--user_os_matcher', required=True, help='String to match in User Agent')
    args = parser.parse_args()

    branch = args.branch
    shortrev = args.shortrev
    hash = args.hash
    author = args.author
    description = args.description
    target_system = args.target_system
    build_url = args.build_url
    user_os_matcher = args.user_os_matcher

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
