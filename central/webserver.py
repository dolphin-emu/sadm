"""Web server module that received events from WebHooks and user interactions
and shows a list of recent events."""

from config import cfg

import events
import utils

import bottle
import cgi
import collections
import datetime
import hashlib
import hmac
import io
import json
import logging

# Buildbot sometimes batches events and gets rejected by the small default
# bottle size. Increase it.
bottle.BaseRequest.MEMFILE_MAX = 64 * 1024 * 1024  # 32MB


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


@bottle.route('/gh/hook/', method='POST')
def gh_hook():
    if 'X-Hub-Signature' not in bottle.request.headers:
        logging.error('Unsigned POST request to webhook URL.')
        raise HTTPError(403, 'Request not signed (no X-Hub-Signature)')
    payload = bottle.request.body.read()
    received_sig = bottle.request.headers['X-Hub-Signature']
    if not received_sig.startswith('sha1='):
        logging.error('X-Hub-Signature not HMAC-SHA1 (%r)' % received_sig)
        raise HTTPError(500, 'X-Hub-Signature not HMAC-SHA1')
    received_sig = received_sig.split('=', 1)[1]
    computed_sig = hmac.new(cfg.github.hook_hmac_secret.encode('ascii'),
                            payload, hashlib.sha1).hexdigest()
    if received_sig != computed_sig:
        logging.error('Received signature %r does not match' % received_sig)
        raise HTTPError(403, 'Signature mismatch')

    evt_type = bottle.request.headers['X-Github-Event']
    evt = events.RawGHHook(evt_type, bottle.request.json)
    events.dispatcher.dispatch('webserver', evt)

    return 'OK'


@bottle.route('/buildbot/', method='POST')
def buildbot_hook():
    packets = bottle.request.POST['packets']
    packets = json.loads(packets)

    for packet in packets:
        evt = events.RawBBHook(packet['event'], packet)
        events.dispatcher.dispatch('webserver', evt)

    return 'OK'


def start():
    """Starts the web server."""
    port = cfg.web.port

    events.dispatcher.register_target(event_logger)

    logging.info('Starting web server: port=%d' % port)
    utils.DaemonThread(target=bottle.run,
                       kwargs={ 'host': cfg.web.bind,
                                'port': cfg.web.port }).start()
