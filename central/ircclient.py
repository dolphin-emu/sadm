"""IRC client module that sends events to an IRC channel with nice,
human-readable formatting. Also receives events from registered users."""

from config import cfg
from pypeul import IRC, Tags

import events

import logging
import queue
import utils

class Bot(IRC):
    def __init__(self, cfg):
        super(Bot, self).__init__()
        self.cfg = cfg

    def start(self):
        self.connect(self.cfg.server, self.cfg.port, self.cfg.ssl)
        self.ident(self.cfg.nick)
        self.set_reconnect(lambda n: 10 * n)
        self.run()

    def on_ready(self):
        for chan in self.cfg.channels:
            self.join(chan)

    def say(self, what):
        for chan in self.cfg.channels:
            self.message(chan, what)

    def on_channel_message(self, who, channel, msg):
        if self.cfg.nick in msg:
            self.message(channel, Tags.LtGreen(Tags.Bold('WARK WARK WARK')))

        evt = events.IRCMessage(str(who), channel, msg)
        events.dispatcher.dispatch('ircclient', evt)


class EventTarget(events.EventTarget):
    def __init__(self, bot):
        self.bot = bot
        self.queue = queue.Queue()

    def push_event(self, evt):
        self.queue.put(evt)

    def accept_event(self, evt):
        accepted_types = [
            events.GCodeIssue.TYPE,
        ]
        return evt.type in accepted_types

    def run(self):
        while True:
            evt = self.queue.get()
            if evt.type == events.GCodeIssue.TYPE:
                self.handle_gcode_issue(evt)
            else:
                logging.warn('Got unknown event for irc: %r' % evt.type)

    def handle_gcode_issue(self, evt):
        """Sends an IRC message notifying of a new GCode issue update."""
        author = Tags.Green(evt.author)
        url = Tags.UnderlineBlue(utils.shorten_url(evt.url))
        if evt.new:
            msg = 'Issue %d created: "%s" by %s - %s'
            msg = msg % (evt.issue, evt.title, author, url)
        else:
            msg = 'Update %d to issue %d ("%s") by %s - %s'
            msg = msg % (evt.update, evt.issue, evt.title, author, url)
        self.bot.say(msg)

def start():
    """Starts the IRC client."""
    server = cfg.irc.server
    port = cfg.irc.port
    ssl = cfg.irc.ssl
    nick = cfg.irc.nick
    channels = cfg.irc.channels

    logging.info('Starting IRC client: server=%r port=%d ssl=%s nick=%r '
                 'channels=%r', server, port, ssl, nick, channels)

    bot = Bot(cfg.irc)
    utils.DaemonThread(target=bot.start).start()

    evt_target = EventTarget(bot)
    events.dispatcher.register_target(evt_target)
    utils.DaemonThread(target=evt_target.run).start()
