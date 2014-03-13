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

    def push(self, evt):
        self.queue.put(evt)

    def run(self):
        while True:
            evt = self.queue.get()

            if not evt.safe_author:
                status_evt = events.PullRequestBuildStatus(evt.repo,
                        evt.head_sha, 'failure', '',
                        'PR not built because %s is not auto-trusted.'
                            % evt.author)
                events.dispatcher.dispatch('prbuilder', status_evt)
                continue

            # To check if a PR is mergeable, we need to request it directly.
            pr = requests.get('https://api.github.com/repos/%s/pulls/%s'
                    % (evt.repo, evt.id)).json()
            logging.info('PR %s mergeable: %s (%s)', evt.id, pr['mergeable'],
                    pr['mergeable_state'])

            if not pr['mergeable']:
                status_evt = events.PullRequestBuildStatus(evt.repo,
                        evt.head_sha, 'failure', '',
                        'PR cannot be merged, please rebase.')
                events.dispatcher.dispatch('prbuilder', status_evt)
                continue

            patch = requests.get('https://github.com/%s/pull/%d.patch'
                                 % (evt.repo, evt.id)).text
            req = make_build_request(evt.repo, evt.id,
                    '%d-%s' % (evt.id, evt.head_sha[:6]), evt.base_sha,
                    evt.head_sha, patch,
                    'Central (on behalf of: %s)' % evt.author,
                    'Auto build for PR #%d (%s).' % (evt.id, evt.head_sha))
            send_build_request(req)

            status_evt = events.PullRequestBuildStatus(evt.repo, evt.head_sha,
                    'pending', cfg.buildbot.url + '/waterfall',
                    'Auto build in progress')
            events.dispatcher.dispatch('prbuilder', status_evt)


class PullRequestListener(events.EventTarget):
    """Listens for new or synchronized pull requests and starts a new build."""

    def __init__(self, builder):
        super(PullRequestListener, self).__init__()
        self.builder = builder

    def accept_event(self, evt):
        return evt.type == events.GHPullRequest.TYPE

    def push_event(self, evt):
        if evt.action != 'opened' or evt.action != 'synchronize':
            if evt.repo in cfg.github.maintain:
                self.builder.push(evt)


class BuildStatusCollector:
    def __init__(self):
        self.queue = queue.Queue()
        self.successes = collections.defaultdict(int)

    def push(self, evt):
        self.queue.put(evt)

    def run(self):
        while True:
            evt = self.queue.get()
            builder = evt.payload.build.builderName
            props = { a: b for (a, b, _) in evt.payload.build.properties }
            if 'headrev' not in props or 'repo' not in props:
                continue  # Not PR build.
            headrev = props['headrev']
            repo = props['repo']
            buildnumber = props['buildnumber']
            success = evt.payload.results in (0, 1)  # SUCCESS/WARNING

            url = cfg.buildbot.url + '/builders/%s/builds/%s' % (builder,
                                                                 buildnumber)

            if not success:
                evt = events.PullRequestBuildStatus(repo, headrev, 'failure',
                        url, 'Build failed on builder %s' % builder)
                events.dispatcher.dispatch('buildbot', evt)
            else:
                self.successes[headrev] += 1
                if self.successes[headrev] == len(cfg.buildbot.pr_builders):
                    evt = events.PullRequestBuildStatus(repo, headrev,
                            'success', url, 'Build succeeded on the Buildbot.')
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
    utils.DaemonThread(target=pr_builder.run).start()

    collector = BuildStatusCollector()
    events.dispatcher.register_target(BBHookListener(collector))
    utils.DaemonThread(target=collector.run).start()
