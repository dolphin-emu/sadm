"""Events module, including all the supported event constructors and the global
event dispatcher."""

import utils

import functools
import logging


class EventTarget:
    def push_event(self, evt):
        logging.error('push_event not redefined in EventTarget subclass')

    def accept_event(self, evt):
        return True


class Dispatcher:
    def __init__(self, targets=None):
        self.targets = targets or []

    def register_target(self, target):
        self.targets.append(target)

    def dispatch(self, source, evt):
        transmitted = { 'source': source }
        transmitted.update(evt)
        transmitted = utils.ObjectLike(transmitted)
        for tgt in self.targets:
            try:
                if tgt.accept_event(transmitted):
                    tgt.push_event(transmitted)
            except Exception:
                logging.exception('Failed to pass event to %r' % tgt)
                continue


dispatcher = Dispatcher()


# Event constructors. Events are dictionaries, with the following keys being
# mandatory:
#   - type: The event type (string).
#   - source: The event source (string).

def event(type):
    def decorator(f):
        @functools.wraps(f)
        def wrapper(*args, **kwargs):
            evt = f(*args, **kwargs)
            evt['type'] = type
            return evt
        wrapper.TYPE = type
        return wrapper
    return decorator

@event('internal_log')
def InternalLog(level : str, pathname : str, lineno : int, msg : str,
                args : str):
    return { 'level': level, 'pathname': pathname, 'lineno': lineno,
             'msg': msg, 'args': args }

@event('irc_message')
def IRCMessage(who : str, where : str, what : str):
    return { 'who': who, 'where': where, 'what': what }

@event('gcode_issue')
def GCodeIssue(new : bool, update : int, issue : int, title : str,
               author : str, url : str):
    return { 'new': new, 'update': update, 'issue': issue, 'title': title,
             'author': author, 'url': url }

@event('raw_gh_hook')
def RawGHHook(gh_type : str, raw : dict):
    return { 'gh_type': gh_type, 'raw': raw }

@event('gh_push')
def GHPush(repo : str, pusher : str, before_sha : str, after_sha : str,
           commits : list, base_ref_name : str, ref_name : str, ref_type : str,
           created : bool, deleted : bool, forced : bool):
    return { 'repo': repo, 'pusher': pusher, 'before_sha': before_sha,
             'after_sha': after_sha, 'commits': commits,
             'base_ref_name': base_ref_name, 'ref_name': ref_name,
             'ref_type': ref_type, 'created': created, 'deleted': deleted,
             'forced': forced }

@event('gh_pull_request')
def GHPullRequest(repo : str, author : str, action : str, id : int,
                  title : str, base_ref_name : str, head_ref_name : str,
                  url : str):
    return { 'repo': repo, 'author': author, 'action': action, 'id': id,
             'title': title, 'base_ref_name': base_ref_name, 'url': url,
             'head_ref_name': head_ref_name }

@event('gh_pull_request_comment')
def GHPullRequestComment(repo : str, author : str, id : int, hash : str,
                         url : str):
    return { 'repo': repo, 'author': author, 'id': id, 'hash': hash,
             'url': url }

@event('gh_issue_comment')
def GHIssueComment(repo : str, author : str, id : int, title : str, url : str):
    return { 'repo': repo, 'author': author, 'id': id, 'title': title,
             'url': url }

@event('gh_commit_comment')
def GHCommitComment(repo : str, author : str, commit : str, url : str):
    return { 'repo': repo, 'author': author, 'commit': commit, 'url': url }
