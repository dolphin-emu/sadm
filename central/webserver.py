"""Web server module that received events from WebHooks and user interactions
and shows a list of recent events."""

from config import cfg

import events
import utils

import bottle
import cgi
import collections
import datetime
import io
import logging


class EventLogger(events.EventTarget):
    def __init__(self):
        self.events = collections.deque(maxlen=25)
        self.per_type = collections.defaultdict(
                lambda: collections.deque(maxlen=25))

    def push_event(self, evt):
        ts = datetime.datetime.now()
        self.events.append((ts, evt))
        self.per_type[evt.type].append((ts, evt))
event_logger = EventLogger()


@bottle.route('/')
def status():
    out = io.StringIO()
    out.write('<h2 style="text-align: center; background: #0ff">Status for Dolphin Central</h2>')

    def display_recent_events(l):
        out.write('<pre>')
        for ts, e in reversed(l):
            out.write(cgi.escape('%s\t%s\n' % (ts.isoformat(), e)))
        out.write('</pre>')

    out.write('<h3>Recent events</h3>')
    display_recent_events(event_logger.events)
    for type, events in sorted(event_logger.per_type.items()):
        out.write('<h3>Recent %r events</h3>' % type)
        display_recent_events(events)

    return out.getvalue()


def start():
    """Starts the web server."""
    port = cfg.web.port

    events.dispatcher.register_target(event_logger)

    logging.info('Starting web server: port=%d' % port)
    utils.DaemonThread(target=bottle.run,
                       kwargs={ 'host': '0.0.0.0',
                                'port': cfg.web.port }).start()
