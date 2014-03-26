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


TRUSTED_USERS = set()
def sync_trusted_users():
    """Synchronizes the list of trusted users by querying a given group."""
    global TRUSTED_USERS
    org = cfg.github.trusted_users.group.split('/')[0]
    team = cfg.github.trusted_users.group.split('/')[1]
    logging.info('Refreshing list of trusted users (from %s/%s)',
                 org, team)

    teams = requests.get('https://api.github.com/orgs/%s/teams' % org,
                         auth=basic_auth()).json()
    team_id = None
    for t in teams:
        if t['slug'] == team:
            team_id = t['id']
            break

    if team_id is not None:
        team_info = requests.get('https://api.github.com/teams/%s/members'
                                 % team_id, auth=basic_auth()).json()
        trusted = set()
        for member in team_info:
            trusted.add(member['login'])
        TRUSTED_USERS = trusted
        logging.info('New GH trusted users: %s', ','.join(trusted))
    else:
        logging.error('Could not find team %r in org %r', team, org)


def is_safe_author(login):
    return login in TRUSTED_USERS


def periodic_hook_maintainer():
    """Function that checks watched repositories for presence of a webhook that
    points to us. If not present, installs the hook."""

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


class GHHookEventParser(events.EventTarget):
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

    def convert_pull_request_event(self, raw):
        repo = raw.repository.owner.login + '/' + raw.repository.name
        author = raw.sender.login
        base_ref_name = raw.pull_request.base.label.split(':')[-1]
        head_ref_name = raw.pull_request.head.label.split(':')[-1]
        base_sha = raw.pull_request.base.sha
        head_sha = raw.pull_request.head.sha
        return events.GHPullRequest(repo, author, raw.action,
                                    raw.pull_request.number,
                                    raw.pull_request.title, base_ref_name,
                                    head_ref_name, base_sha, head_sha,
                                    raw.pull_request.html_url,
                                    is_safe_author(author))

    def convert_pull_request_comment_event(self, raw):
        repo = raw.repository.owner.login + '/' + raw.repository.name
        id = int(raw.comment.pull_request_url.split('/')[-1])
        return events.GHPullRequestComment(repo, raw.sender.login, id,
                                           raw.comment.commit_id,
                                           raw.comment.html_url)

    def convert_issue_comment_event(self, raw):
        author = raw.sender.login
        repo = raw.repository.owner.login + '/' + raw.repository.name
        id = int(raw.issue.html_url.split('/')[-1])
        return events.GHIssueComment(repo, author, id, raw.issue.title,
                                     raw.comment.html_url,
                                     is_safe_author(author), raw.comment.body)

    def convert_commit_comment_event(self, raw):
        repo = raw.repository.owner.login + '/' + raw.repository.name
        return events.GHCommitComment(repo, raw.sender.login,
                                      raw.comment.commit_id,
                                      raw.comment.html_url)

    def push_event(self, evt):
        if evt.gh_type == 'push':
            obj = self.convert_push_event(evt.raw)
        elif evt.gh_type == 'pull_request':
            obj = self.convert_pull_request_event(evt.raw)
        elif evt.gh_type == 'pull_request_review_comment':
            obj = self.convert_pull_request_comment_event(evt.raw)
        elif evt.gh_type == 'issue_comment':
            obj = self.convert_issue_comment_event(evt.raw)
        elif evt.gh_type == 'commit_comment':
            obj = self.convert_commit_comment_event(evt.raw)
        else:
            logging.error('Unhandled event type %r in GH parser' % evt.gh_type)
            return
        events.dispatcher.dispatch('ghhookparser', obj)


class GHPRStatusUpdater(events.EventTarget):
    def accept_event(self, evt):
        return evt.type == events.PullRequestBuildStatus.TYPE

    def push_event(self, evt):
        url = 'https://api.github.com/repos/' + evt.repo + '/statuses/' + evt.hash
        data = { 'state': evt.status, 'target_url': evt.url,
                 'description': evt.description }
        requests.post(url, headers={'Content-Type': 'application/json'},
                      data=json.dumps(data), auth=basic_auth())


def start():
    """Starts all the GitHub related services."""

    events.dispatcher.register_target(GHHookEventParser())
    events.dispatcher.register_target(GHPRStatusUpdater())

    utils.spawn_periodic_task(600, periodic_hook_maintainer)
    utils.spawn_periodic_task(cfg.github.trusted_users.refresh_interval,
                              sync_trusted_users)
