"""GitHub module that handles most interactions with GitHub. It handles
incoming events but also provides an API."""

from config import cfg

import events
import json
import logging
import textwrap
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


def user_from_oauth(token):
    return requests.get('https://api.github.com/user',
                        headers={'Authorization': 'token ' + token}).json()


def get_pull_request(owner, repo, pr_id):
    return requests.get('https://api.github.com/repos/%s/%s/pulls/%s'
                        % (owner, repo, pr_id)).json()


def get_pull_request_comments(pr):
    comments = []
    url = pr['_links']['comments']['href']
    while True:
        r = requests.get(url)
        comments.extend(r.json())
        if 'link' in r.headers and 'next' in r.links:
            url = r.links['next']['url']
        else:
            break
    return comments


def delete_comment(owner, repo, cmt_id):
    requests.delete('https://api.github.com/repos/%s/%s/issues/comments/%d' %
            (owner, repo, cmt_id), auth=basic_auth())


def post_comment(owner, repo, pr_id, body):
    requests.post('https://api.github.com/repos/%s/%s/issues/%s/comments' %
            (owner, repo, pr_id), data=json.dumps({'body': body}),
            headers={'Content-Type': 'application/json'},
            auth=basic_auth())


def is_pull_request_buildable(pr):
    statuses = requests.get(pr['_links']['statuses']['href']).json()
    if not statuses:
        return False
    st = list(sorted((s['id'], s['state']) for s in statuses))[-1]
    return st[1] == 'success'


def is_pull_request_self_mergeable(pr):
    comments = get_pull_request_comments(pr)
    comments = [c for c in comments if c['user']['login'] in CORE_USERS]
    allowed = False
    for c in comments:
        if cfg.github.allow_self_merge_command in c['body']:
            allowed = True
        if cfg.github.disallow_self_merge_command in c['body']:
            allowed = False
    return allowed


def merge_pr(pr):
    merge_url = pr['_links']['self']['href'] + '/merge'
    requests.put(merge_url,
        data=json.dumps({'commit_message': pr['title']}),
        auth=basic_auth())

def request_get_all(url):
    """Github uses Link header for pagination, this loops through all pages."""
    data = []
    r = requests.get(url, auth=basic_auth())
    data += r.json()
    while "next" in r.links:
        r = requests.get(r.links['next']['url'], auth=basic_auth())
        data += r.json()
    return data

TRUSTED_USERS = set()
CORE_USERS = set()
def sync_github_group(group, group_name):
    """Synchronizes the list of trusted users by querying a given group."""
    org = group_name.split('/')[0]
    team = group_name.split('/')[1]
    logging.info('Refreshing list of trusted users (from %s/%s)',
                 org, team)

    teams = request_get_all('https://api.github.com/orgs/%s/teams' % org)
    team_id = None
    for t in teams:
        if t['slug'] == team:
            team_id = t['id']
            break

    if team_id is not None:
        team_info = request_get_all('https://api.github.com/teams/%s/members' % team_id)
        group.clear()
        for member in team_info:
            group.add(member['login'])
        logging.info('New GH %s: %s', group_name, ','.join(group))
    else:
        logging.error('Could not find team %r in org %r', team, org)


def sync_trusted_users():
    sync_github_group(TRUSTED_USERS, cfg.github.trusted_users.group)


def sync_core_users():
    sync_github_group(CORE_USERS, cfg.github.core_users.group)


def is_safe_author(login):
    return login in TRUSTED_USERS


def periodic_hook_maintainer():
    """Function that checks watched repositories for presence of a webhook that
    points to us. If not present, installs the hook."""

    logging.info('Checking watched repositories for webhook presence')
    for repo in watched_repositories():
        hs = request_get_all('https://api.github.com/repos/%s/hooks' % repo)
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
        return events.GHPullRequestComment(repo, raw.sender.login, raw.action,
                                           id, raw.comment.commit_id,
                                           raw.comment.html_url)

    def convert_issue_comment_event(self, raw):
        author = raw.sender.login
        repo = raw.repository.owner.login + '/' + raw.repository.name
        id = int(raw.issue.html_url.split('/')[-1])
        return events.GHIssueComment(repo, author, id, raw.issue.title,
                                     raw.comment.html_url,
                                     is_safe_author(author), raw.comment.body,
                                     raw)

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
        return evt.type == events.BuildStatus.TYPE

    def push_event(self, evt):
        if evt.pr is None:
            return

        if evt.pending:
            state = 'pending'
        elif evt.success:
            state = 'success'
        else:
            state = 'failure'

        url = 'https://api.github.com/repos/' + evt.repo + '/statuses/' + evt.hash
        data = { 'state': state, 'target_url': evt.url,
                'description': evt.description, 'context': evt.service }
        requests.post(url, headers={'Content-Type': 'application/json'},
                      data=json.dumps(data), auth=basic_auth())


class GHAllowMergeEditer(events.EventTarget):
    def accept_event(self, evt):
        return evt.type == events.GHIssueComment.TYPE

    def push_event(self, evt):
        if evt.author not in CORE_USERS:
            return
        if cfg.github.allow_self_merge_command not in evt.body:
            return
        pr_author = evt.raw.issue.user.login
        merge_url = cfg.web.external_url + '/gh/merge/%s/%s/' % (
                evt.repo, evt.id)
        new_body = '@%s: This comment grants you the permission to merge ' \
                   'this pull request whenever you think it is ready. ' \
                   'After addressing the remaining comments, click ' \
                   '[this link to merge](%s).\n\n---\n\n'
        new_body %= (pr_author, merge_url)
        new_body += evt.body
        requests.patch(evt.raw.comment.url,
                data=json.dumps({'body': new_body}),
                auth=basic_auth())


class GHFifoCIEditer(events.EventTarget):
    MAGIC_WORDS = 'automated-fifoci-reporter'

    def accept_event(self, evt):
        return evt.type == events.PullRequestFifoCIStatus.TYPE

    def push_event(self, evt):
        # Get FifoCI side status
        url = cfg.fifoci.url + '/version/%s/json/' % evt.hash
        diff_data = requests.get(url).json()
        owner, repo = evt.repo.split('/')
        pr = get_pull_request(owner, repo, evt.pr)
        comments = get_pull_request_comments(pr)
        comments = [c for c in comments
                      if c['user']['login'] == cfg.github.account.login]

        body = textwrap.dedent('''\
            [FifoCI](%s/about/) detected that this change impacts graphical \
            rendering. Here are the [behavior differences](%s/version/%s/) \
            detected by the system:

        ''' % (cfg.fifoci.url, cfg.fifoci.url, evt.hash))
        for diff in diff_data:
            l = '* `%s` on `%s`: ' % (diff['dff'], diff['type'])
            if diff['failure']:
                l += '[failed to render]'
            else:
                l += '[diff]'
            l += '(%s%s)' % (cfg.fifoci.url, diff['url'])
            body += l + '\n'
        body += '\n<sub><sup>' + self.MAGIC_WORDS + '</sup></sub>'

        if comments and comments[-1]['body'] == body:
            return

        for c in comments:
            if self.MAGIC_WORDS in c['body']:
                delete_comment(owner, repo, c['id'])

        if not diff_data:
            return

        post_comment(owner, repo, evt.pr, body)

def start():
    """Starts all the GitHub related services."""

    events.dispatcher.register_target(GHHookEventParser())
    events.dispatcher.register_target(GHPRStatusUpdater())
    events.dispatcher.register_target(GHAllowMergeEditer())
    events.dispatcher.register_target(GHFifoCIEditer())

    utils.spawn_periodic_task(600, periodic_hook_maintainer)
    utils.spawn_periodic_task(cfg.github.trusted_users.refresh_interval,
                              sync_trusted_users)
    utils.spawn_periodic_task(cfg.github.core_users.refresh_interval,
                              sync_core_users)
