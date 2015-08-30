"""Transforms raw Redmine issue events into higher level ones.

Will potentially also have more complex processing in the future.
"""

from config import cfg

import events


class Reactor(events.EventTarget):
    def accept_event(self, evt):
        return evt.type == events.RawRedmineHook.TYPE

    def push_event(self, evt):
        if evt.rm_type not in ('opened', 'updated'):
            pass  # Not handled yet.
        new = (evt.rm_type == 'opened')
        if new:
            update = 0
        else:
            update = evt.raw.issue.lock_version
        issue = evt.raw.issue.id
        title = evt.raw.issue.subject
        if new:
            author = evt.raw.issue.author.login
        else:
            author = evt.raw.journal.author.login
        url = '%sissues/%s' % (cfg.redmine.url, issue)
        events.dispatcher.dispatch('redmine',
                events.Issue(new, update, issue, title, author, url))


def start():
    """Starts the Redmine events reactor."""
    events.dispatcher.register_target(Reactor())
