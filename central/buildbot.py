"""Buildbot module that handles communications between the Buildbot and
GitHub."""

from config import cfg

import events
import utils

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


def make_build_request(jobid, baserev, patch, who, comment):
    """Creates a build request binary blob in the format expected by the
    buildbot."""

    request_dict = {
        'branch': '',
        'builderNames': cfg.buildbot.pr_builders,
        'jobid': jobid,
        'baserev': baserev,
        'patch_level': 1,
        'patch_body': patch,
        'who': who,
        'comment': comment,
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
            patch = requests.get('https://github.com/%s/pull/%d.patch'
                                 % (evt.repo, evt.id)).text
            req = make_build_request('pr-%d-%s' % (evt.id, evt.head_sha),
                                     evt.base_sha, patch,
                                     'Central (on behalf of: %s)' % evt.author,
                                     'Auto build for PR #%d (%s)' % (evt.id,
                                                                     evt.head_sha))
            send_build_request(req)


class PullRequestListener(events.EventTarget):
    """Listens for new or synchronized pull requests and starts a new build."""

    def __init__(self, builder):
        super(PullRequestListener, self).__init__()
        self.builder = builder

    def accept_event(self, evt):
        return evt.type == events.GHPullRequest.TYPE

    def push_event(self, evt):
        if evt.action != 'opened' or evt.action != 'synchronize':
            if evt.safe_author:
                if evt.repo in cfg.github.maintain:
                    self.builder.push(evt)


def start():
    """Starts all the Buildbot related services."""

    pr_builder = PullRequestBuilder()
    events.dispatcher.register_target(PullRequestListener(pr_builder))
    utils.DaemonThread(target=pr_builder.run).start()
