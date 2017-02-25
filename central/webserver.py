"""Web server module that received events from WebHooks and user interactions
and shows a list of recent events."""

from config import cfg

import events
import utils

import base64
import bottle
import cgi
import collections
import datetime
import functools
import hashlib
import hmac
import io
import jinja2
import json
import logging
import os
import os.path
import requests
import urllib.parse

# Buildbot sometimes batches events and gets rejected by the small default
# bottle size. Increase it.
bottle.BaseRequest.MEMFILE_MAX = 64 * 1024 * 1024  # 32MB

_JINJA_ENV = None


def render_template(template, **kwargs):
    global _JINJA_ENV
    if _JINJA_ENV is None:
        this_dir = os.path.dirname(__file__)
        loader = jinja2.FileSystemLoader(os.path.join(this_dir, 'templates'))
        _JINJA_ENV = jinja2.Environment(loader=loader, autoescape=True)
    return _JINJA_ENV.get_template(template).render(**kwargs)


def requires_gh_auth(requested_scope):
    """Require GitHub OAuth authentication for the given scope. Stores the
    token and scope in HttpOnly, Secure, encrypted cookies.

    Cookies are encrypted using the OAuth client secret.
    """

    def decorator(func):
        @functools.wraps(func)
        def wrapper(*args, **kwargs):
            req = bottle.request
            key = cfg.github.oauth.client_secret
            scope = set()
            if req.get_cookie('gh_oauth_token', secret=key) is not None and \
                    req.get_cookie('gh_oauth_scope', secret=key) is not None:
                token = req.get_cookie('gh_oauth_token', secret=key)
                scope = req.get_cookie('gh_oauth_scope', secret=key)
                token = utils.decrypt_data(
                    token.encode('ascii'), cfg.github.oauth.client_secret)
                scope = utils.decrypt_data(
                    scope.encode('ascii'), cfg.github.oauth.client_secret)
                scope = set(scope.split(','))
                if requested_scope.issubset(scope):
                    req.oauth_token = token
                    return func(*args, **kwargs)
            return ask_for_gh_auth(requested_scope | scope)

        return wrapper

    return decorator


def ask_for_gh_auth(requested_scope):
    """Starts a GitHub OAuth flow to ask for the given requested scope."""
    qs = urllib.parse.urlencode({'r': bottle.request.url})
    redirect_url = cfg.web.external_url + '/gh/oauth/?' + qs

    args = {'client_id': cfg.github.oauth.client_id,
            'redirect_uri': redirect_url,
            'scope': ','.join(requested_scope),
            'state': base64.b64encode(os.urandom(16)).decode('ascii')}
    qs = urllib.parse.urlencode(args)
    oauth_url = 'https://github.com/login/oauth/authorize?' + qs
    bottle.redirect(oauth_url)


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
    out.write(
        '<h2 style="text-align: center; background: #0ff">Status for Dolphin Central</h2>')

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
        raise bottle.HTTPError(403, 'Request not signed (no X-Hub-Signature)')
    payload = bottle.request.body.read()
    received_sig = bottle.request.headers['X-Hub-Signature']
    if not received_sig.startswith('sha1='):
        logging.error('X-Hub-Signature not HMAC-SHA1 (%r)' % received_sig)
        raise bottle.HTTPError(500, 'X-Hub-Signature not HMAC-SHA1')
    received_sig = received_sig.split('=', 1)[1]
    computed_sig = hmac.new(
        cfg.github.hook_hmac_secret.encode('ascii'), payload,
        hashlib.sha1).hexdigest()
    if received_sig != computed_sig:
        logging.error('Received signature %r does not match' % received_sig)
        raise bottle.HTTPError(403, 'Signature mismatch')

    evt_type = bottle.request.headers['X-Github-Event']
    evt = events.RawGHHook(evt_type, bottle.request.json)
    events.dispatcher.dispatch('webserver', evt)

    return 'OK'


@bottle.route('/gh/oauth/')
def gh_oauth():
    args = bottle.request.query
    if 'code' not in args or 'r' not in args:
        raise bottle.HTTPError(404, 'Missing arguments')
    response = requests.post('https://github.com/login/oauth/access_token',
                             data={'client_id': cfg.github.oauth.client_id,
                                   'client_secret':
                                   cfg.github.oauth.client_secret,
                                   'code': args['code']},
                             headers={'Accept': 'application/json'}).json()
    if 'access_token' not in response:
        raise bottle.HTTPError(403, 'No response token from GitHub')

    token = utils.encrypt_data(response['access_token'].encode('ascii'),
                               cfg.github.oauth.client_secret)
    scope = utils.encrypt_data(response['scope'].encode('ascii'),
                               cfg.github.oauth.client_secret)
    bottle.response.set_cookie('gh_oauth_token',
                               token,
                               secure=True,
                               httponly=True,
                               path='/',
                               secret=cfg.github.oauth.client_secret)
    bottle.response.set_cookie('gh_oauth_scope',
                               scope,
                               secure=True,
                               httponly=True,
                               path='/',
                               secret=cfg.github.oauth.client_secret)

    bottle.redirect(args['r'])


@bottle.route('/gh/merge/<owner>/<repo>/<pr_id>/', method='GET')
@requires_gh_auth(set())
def gh_merge(**kwargs):
    return render_template('merge-pr.html', **kwargs)


@bottle.route('/gh/merge/do/<owner>/<repo>/<pr_id>/', method='POST')
@requires_gh_auth(set())
def gh_merge_do(owner, repo, pr_id):
    import github
    user = github.user_from_oauth(bottle.request.oauth_token)
    pr = github.get_pull_request(owner, repo, pr_id)
    if 'login' not in user:
        raise bottle.HTTPError(403, 'Could not identify user')
    if 'user' not in pr:
        raise bottle.HTTPError(403, 'Could not identify PR')
    if user['login'] != pr['user']['login']:
        raise bottle.HTTPError(403, 'Merge requester is not the PR author')
    if pr['merged']:
        raise bottle.HTTPError(403, 'PR is already merged')
    if not pr['mergeable']:
        raise bottle.HTTPError(403, 'PR cannot be merged. Please rebase')
    if not github.is_pull_request_buildable(pr):
        raise bottle.HTTPError(403, 'PR status not green. Wait or fix errors')
    if not github.is_pull_request_self_mergeable(pr):
        raise bottle.HTTPError(403, 'Nobody allowed you to merge this PR')
    github.merge_pr(pr)
    bottle.redirect(pr['html_url'])


@bottle.route('/buildbot', method='POST')
def buildbot_hook():
    packets = bottle.request.POST['packets']
    packets = json.loads(packets)

    for packet in packets:
        evt = events.RawBBHook(packet['event'], packet)
        events.dispatcher.dispatch('webserver', evt)

    return 'OK'


@bottle.route('/redmine/', method='POST')
def redmine_hook():
    packet = bottle.request.json
    if 'payload' not in packet:
        raise bottle.HTTPError(400, 'Could not find payload object')
    packet = packet['payload']

    evt = events.RawRedmineHook(packet['action'], packet)
    events.dispatcher.dispatch('webserver', evt)

    return 'OK'


def start():
    """Starts the web server."""
    port = cfg.web.port

    events.dispatcher.register_target(event_logger)

    logging.info('Starting web server: port=%d' % port)
    utils.DaemonThread(target=bottle.run,
                       kwargs={'host': cfg.web.bind,
                               'port': cfg.web.port}).start()
