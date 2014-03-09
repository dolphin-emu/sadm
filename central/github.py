"""GitHub module that handles most interactions with GitHub. It handles
incoming events but also provides an API."""

from config import cfg

import events
import json
import logging
import time
import utils

import requests


GH_WEBHOOK_EVENTS = [
    'push',
    'pull_request',
    'pull_request_review_comment',
    'commit_comment',
    'issue_comment',
]


def basic_auth():
    return (cfg.github.account.token, 'x-oauth-basic')


def watched_repositories():
    return cfg.github.maintain + cfg.github.notify


def webhook_url():
    return cfg.web.external_url + '/gh/hook/'


def periodic_hook_maintainer():
    """Function that checks watched repositories for presence of a webhook that
    points to us. If not present, installs the hook."""

    while True:
        logging.info('Checking watched repositories for webhook presence')
        for repo in watched_repositories():
            hs = requests.get('https://api.github.com/repos/%s/hooks' % repo,
                              auth=basic_auth()).json()
            hook_present = False
            for h in hs:
                if "config" not in h:
                    continue
                config = h["config"]
                if "url" not in config:
                    continue
                if config["url"] != webhook_url():
                    continue
                hook_present = True
                break

            hook_data = {
                'name': 'web',
                'active': 'true',
                'events': GH_WEBHOOK_EVENTS,
                'config': {
                    'url': webhook_url(),
                    'content_type': 'json',
                    'secret': cfg.github.hook_hmac_secret,
                    'insecure_ssl': '0',
                },
            }

            if hook_present:
                logging.info('Watched repo %r has our hook installed' % repo)
                url = h['url']
                method = requests.patch
            else:
                logging.warning('Repo %r is missing our hook, installing'
                                % repo)
                url = 'https://api.github.com/repos/%s/hooks' % repo
                method = requests.post

            method(url, headers={'Content-Type': 'application/json'},
                   data=json.dumps(hook_data), auth=basic_auth())
        time.sleep(600)


class GHEventParser(events.EventTarget):
    def accept_event(self, evt):
        return evt.type == events.RawGHHook.TYPE

    def convert_commit(self, commit):
        commit = utils.ObjectLike(commit)
        return { 'author': commit.author, 'distinct': commit.distinct,
                 'added': commit.added, 'modified': commit.modified,
                 'removed': commit.removed, 'message': commit.message,
                 'url': commit.url, 'hash': commit.id }

    def convert_push_event(self, raw):
        repo = raw.repository.owner.name + '/' + raw.repository.name
        pusher = raw.pusher.name
        before_sha = raw.before
        after_sha = raw.after
        commits = [self.convert_commit(c) for c in raw.commits]
        base_ref = raw.base_ref
        base_ref_name = base_ref.split('/', 2)[2] if base_ref else None
        ref_name = raw.ref.split('/', 2)[2]
        ref_type = raw.ref.split('/', 2)[1]
        created = raw.created
        deleted = raw.deleted
        forced = raw.forced

        return events.GHPush(repo, pusher, before_sha, after_sha, commits,
                             base_ref_name, ref_name, ref_type, created,
                             deleted, forced)

    def push_event(self, evt):
        if evt.gh_type == 'push':
            obj = self.convert_push_event(evt.raw)
        else:
            logging.error('Unhandled event type %r in GH parser' % evt.gh_type)
            return
        events.dispatcher.dispatch('ghparser', obj)

def start():
    """Starts all the GitHub related services."""

    events.dispatcher.register_target(GHEventParser())

    utils.DaemonThread(target=periodic_hook_maintainer).start()
