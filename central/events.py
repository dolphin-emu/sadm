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
            if tgt.accept_event(transmitted):
                tgt.push_event(transmitted)


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

@event('irc_message')
def IRCMessage(who : str, where : str, what : str):
    return { 'who': who, 'where': where, 'what': what }

@event('gcode_issue')
def GCodeIssue(new : bool, update : int, issue : int, title : str,
               author : str, url : str):
    return { 'new': new, 'update': update, 'issue': issue, 'title': title,
             'author': author, 'url': url }
