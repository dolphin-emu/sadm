"""Buildbot module that handles communications between the Buildbot and
GitHub."""

from config import cfg

import events
import utils

import collections
import json
import logging
import os
import os.path
import queue
import re
import requests
import uuid


def make_netstring(s):
    """Creates a netstring from a blob of bytes."""
    return str(len(s)).encode('ascii') + b':' + s + b','


def make_build_request(repo, pr_id, job_id, baserev, headrev, patch, who,
                       comment):
    """Creates a build request binary blob in the format expected by the
    buildbot."""

    request_dict = {
        'branch': '',
        'builderNames': cfg.buildbot.pr_builders,
        'jobid': job_id,
        'baserev': baserev,
        'patch_level': 1,
        'patch_body': patch,
        'who': who,
        'comment': comment,
        'properties': {
            'branchname': 'pr-%d' % pr_id,
            'headrev': headrev,
            'shortrev': headrev[:6],
            'pr_id': pr_id,
            'repo': repo,
        },
    }
    encoded = json.dumps(request_dict, ensure_ascii=True).encode('ascii')
    version = make_netstring(b'5')
    return version + make_netstring(encoded)


def send_build_request(build_request):
    """Stores the build request (atomically) in the buildbot jobdir."""

    path = os.path.join(cfg.buildbot.jobdir, 'tmp', str(uuid.uuid4()))
    open(path, 'wb').write(build_request)
    final_path = os.path.join(cfg.buildbot.jobdir, 'new', str(uuid.uuid4()))
    os.rename(path, final_path)
    logging.info('Sent build request: %r', final_path)


class PullRequestBuilder:
    def __init__(self):
        self.queue = queue.Queue()

    def push(self, in_behalf_of, trusted, repo, pr_id):
        self.queue.put((in_behalf_of, trusted, repo, pr_id))

    def run(self):
        while True:
            in_behalf_of, trusted, repo, pr_id = self.queue.get()

            # To check if a PR is mergeable, we need to request it directly.
            pr = requests.get('https://api.github.com/repos/%s/pulls/%d'
                    % (repo, pr_id)).json()
            logging.info('PR %s mergeable: %s (%s)', pr_id, pr['mergeable'],
                    pr['mergeable_state'])

            base_sha = pr['base']['sha']
            head_sha = pr['head']['sha']

            # check if the PR contains any merge commits
            commits = requests.get('https://api.github.com/repos/%s/pulls/%d/commits'
                    % (repo, pr_id)).json()
            has_merge_commits = any(len(c['parents']) > 1 for c in commits)

            if has_merge_commits:
                status_evt = events.PullRequestBuildStatus(repo, head_sha,
                        'default', 'failure', '',
                        'PR contains a merge commit, please use rebase instead.')
                events.dispatcher.dispatch('prbuilder', status_evt)
                continue

            # mergeable can be None!
            if pr['mergeable'] is False:
                status_evt = events.PullRequestBuildStatus(repo, head_sha,
                        'default', 'failure', '',
                        'PR cannot be merged, please rebase.')
                events.dispatcher.dispatch('prbuilder', status_evt)
                continue

            if not trusted:
                status_evt = events.PullRequestBuildStatus(repo, head_sha,
                        'default', 'failure', '',
                        'PR not built because %s is not auto-trusted.'
                            % in_behalf_of)
                events.dispatcher.dispatch('prbuilder', status_evt)
                continue

            status_evt = events.PullRequestBuildStatus(repo, head_sha,
                        'default', 'success', '',
                        'Very basic checks passed, handed off to Buildbot.')
            events.dispatcher.dispatch('prbuilder', status_evt)

            for builder in cfg.buildbot.pr_builders:
                status_evt = events.PullRequestBuildStatus(repo, head_sha,
                        builder, 'pending', cfg.buildbot.url + '/waterfall',
                        'Auto build in progress')
                events.dispatcher.dispatch('prbuilder', status_evt)

            patch = requests.get('https://github.com/%s/pull/%d.patch'
                                 % (repo, pr_id)).text
            req = make_build_request(repo, pr_id,
                    '%d-%s' % (pr_id, head_sha[:6]), base_sha,
                    head_sha, patch,
                    'Central (on behalf of: %s)' % in_behalf_of,
                    'Auto build for PR #%d (%s).' % (pr_id, head_sha))
            send_build_request(req)


class PullRequestListener(events.EventTarget):
    """Listens for new or synchronized pull requests and starts a new build."""

    def __init__(self, builder):
        super(PullRequestListener, self).__init__()
        self.builder = builder

    def accept_event(self, evt):
        return evt.type == events.GHPullRequest.TYPE

    def push_event(self, evt):
        if evt.action == 'opened' or evt.action == 'synchronize':
            if evt.repo in cfg.github.maintain:
                self.builder.push(evt.author, evt.safe_author, evt.repo,
                                  evt.id)


class ManualPullRequestListener(events.EventTarget):
    """Listens for comments from trusted users on PRs for a keyword to build
    a PR from an untrusted user."""

    def __init__(self, builder):
        super(ManualPullRequestListener, self).__init__()
        self.builder = builder

    def accept_event(self, evt):
        return evt.type == events.GHIssueComment.TYPE

    def push_event(self, evt):
        if not evt.safe_author:
            return
        if cfg.github.rebuild_command.lower() not in evt.body.lower():
            return
        if evt.repo not in cfg.github.maintain:
            return
        self.builder.push(evt.author, evt.safe_author, evt.repo, evt.id)


class IRCRebuildListener(events.EventTarget):
    """Listen for rebuild commands on IRC."""

    def __init__(self, builder):
        super(IRCRebuildListener, self).__init__()
        self.builder = builder

    def accept_event(self, evt):
        return evt.type == events.IRCMessage.TYPE

    def push_event(self, evt):
        trusted = 'o' in evt.modes
        if not evt.direct or not trusted:
            return
        matches = re.search(r'\brebuild (pr ?)?(?P<pr_id>\d+)\b', evt.what, re.I)
        if not matches:
            return
        pr_id = matches.group('pr_id')
        try:
            pr_id = int(pr_id)
        except ValueError:
            return
        self.builder.push(evt.who, trusted, cfg.irc.rebuild_repo, pr_id)


class BuildStatusCollector:
    def __init__(self):
        self.queue = queue.Queue()

    def push(self, evt):
        self.queue.put(evt)

    def run(self):
        while True:
            evt = self.queue.get()
            builder = evt.payload.build.builderName
            props = { a: b for (a, b, _) in evt.payload.build.properties }
            has_all_required = True
            for required in ('headrev', 'repo', 'buildnumber', 'pr_id'):
                if required not in props:
                    has_all_required = False
                    break  # Not PR build.
            if not has_all_required:
                continue
            headrev = props['headrev']
            repo = props['repo']
            buildnumber = props['buildnumber']
            pr_id = props['pr_id']
            success = evt.payload.results in (0, 1)  # SUCCESS/WARNING

            if builder in cfg.buildbot.pr_builders:
                url = cfg.buildbot.url + '/builders/%s/builds/%s' % (
                        builder, buildnumber)

                if not success:
                    evt = events.PullRequestBuildStatus(repo, headrev, builder,
                            'failure', url,
                            'Build failed on builder %s' % builder)
                    events.dispatcher.dispatch('buildbot', evt)
                else:
                    evt = events.PullRequestBuildStatus(repo, headrev, builder,
                            'success', url, 'Build succeeded on the Buildbot.')
                    events.dispatcher.dispatch('buildbot', evt)
            elif builder in cfg.buildbot.fifoci_builders and success:
                evt = events.PullRequestFifoCIStatus(
                        repo, headrev, builder, pr_id)
                events.dispatcher.dispatch('buildbot', evt)


class BBHookListener(events.EventTarget):
    def __init__(self, collector):
        super(BBHookListener, self).__init__()
        self.collector = collector

    def accept_event(self, evt):
        return evt.type == events.RawBBHook.TYPE

    def push_event(self, evt):
        if evt.bb_type == 'buildFinished':
            self.collector.push(evt.raw)


def start():
    """Starts all the Buildbot related services."""

    pr_builder = PullRequestBuilder()
    events.dispatcher.register_target(PullRequestListener(pr_builder))
    events.dispatcher.register_target(ManualPullRequestListener(pr_builder))
    events.dispatcher.register_target(IRCRebuildListener(pr_builder))
    utils.DaemonThread(target=pr_builder.run).start()

    collector = BuildStatusCollector()
    events.dispatcher.register_target(BBHookListener(collector))
    utils.DaemonThread(target=collector.run).start()
