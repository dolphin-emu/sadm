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
            events.GHPush.TYPE,
            events.GHPullRequest.TYPE,
            events.GHPullRequestComment.TYPE,
            events.GHIssueComment.TYPE,
            events.GHCommitComment.TYPE,
        ]
        return evt.type in accepted_types

    def run(self):
        while True:
            evt = self.queue.get()
            if evt.type == events.GCodeIssue.TYPE:
                self.handle_gcode_issue(evt)
            elif evt.type == events.GHPush.TYPE:
                self.handle_gh_push(evt)
            elif evt.type == events.GHPullRequest.TYPE:
                self.handle_gh_pull_request(evt)
            elif evt.type == events.GHPullRequestComment.TYPE:
                self.handle_gh_pull_request_comment(evt)
            elif evt.type == events.GHIssueComment.TYPE:
                self.handle_gh_issue_comment(evt)
            elif evt.type == events.GHCommitComment.TYPE:
                self.handle_gh_commit_comment(evt)
            else:
                logging.error('Got unknown event for irc: %r' % evt.type)

    def format_nickname(self, nickname, avoid_hl=True):
        # Add a unicode zero-width space in the nickname to avoid highlights.
        if avoid_hl and nickname:
            nickname = nickname[0] + '\ufeff' + nickname[1:]
        return Tags.Green(nickname)

    def handle_gcode_issue(self, evt):
        """Sends an IRC message notifying of a new GCode issue update."""
        author = self.format_nickname(evt.author)
        url = Tags.UnderlineBlue(utils.shorten_url(evt.url))
        if evt.new:
            msg = 'Issue %d created: "%s" by %s - %s'
            msg = msg % (evt.issue, evt.title, author, url)
        else:
            msg = 'Update %d to issue %d ("%s") by %s - %s'
            msg = msg % (evt.update, evt.issue, evt.title, author, url)
        self.bot.say(msg)

    def handle_gh_push(self, evt):
        fmt_url = Tags.UnderlineBlue
        fmt_repo_name = Tags.UnderlinePink
        fmt_ref = Tags.Purple
        fmt_hash = lambda h: Tags.Grey(h[:6])

        commits = [utils.ObjectLike(c) for c in evt.commits]
        distinct_commits = [c for c in commits
                            if c.distinct and c.message.strip()]
        num_commits = len(distinct_commits)

        parts = []
        parts.append(Tags.Black('[' + fmt_repo_name(evt.repo) + ']'))
        parts.append(self.format_nickname(evt.pusher))

        if evt.created:
            if evt.ref_type == 'tags':
                parts.append('tagged ' + fmt_ref(evt.ref_name) + ' at')
                parts.append(fmt_ref(evt.base_ref_name) if evt.base_ref_name
                                 else fmt_hash(evt.after_sha))
            else:
                parts.append('created ' + fmt_ref(evt.ref_name))
                if evt.base_ref_name:
                    parts.append('from ' + fmt_ref(evt.base_ref_name))
                elif not distinct_commits:
                    parts.append('at ' + fmt_hash(evt.after_sha))

                if distinct_commits:
                    parts.append('+' + Tags.Bold(str(num_commits)))
                    parts.append('new commit' +
                                    ('s' if num_commits > 1 else ''))
        elif evt.deleted:
            parts.append(Tags.Red('deleted ') + fmt_ref(evt.ref_name))
            parts.append('at ' + fmt_hash(evt.before_sha))
        elif evt.forced:
            parts.append(Tags.Red('force-pushed ') + fmt_ref(evt.ref_name))
            parts.append('from ' + fmt_hash(evt.before_sha) + ' to ' +
                         fmt_hash(evt.after_sha))
        elif commits and not distinct_commits:
            if evt.base_ref_name:
                parts.append('merged ' + fmt_ref(evt.base_ref_name) + ' into '
                             + fmt_ref(evt.ref_name))
            else:
                parts.append('fast-forwarded ' + fmt_ref(evt.ref_name))
                parts.append('from ' + fmt_hash(evt.before_sha) + ' to ' +
                             fmt_hash(evt.after_sha))
        else:
            parts.append('pushed ' + Tags.Bold(str(num_commits)))
            parts.append('new commit' + ('s' if num_commits > 1 else ''))
            parts.append('to ' + fmt_ref(evt.ref_name))

        self.bot.say(' '.join(str(p) for p in parts))

        for commit in distinct_commits[:4]:
            firstline = commit.message.split('\n')[0]
            author = Tags.Green(commit.author.name)
            added = Tags.LtGreen(str(len(commit.added)))
            modified = Tags.LtGreen(str(len(commit.modified)))
            removed = Tags.Red(str(len(commit.removed)))
            url = Tags.UnderlineBlue(utils.shorten_url(commit.url))
            self.bot.say('%s by %s [%s|%s|%s] %s %s' % (
                commit.hash[:6], author, added, modified, removed, url,
                firstline))

        if len(distinct_commits) > 4:
            self.bot.say('... and %d more commits'
                         % (len(distinct_commits) - 4))

    def handle_gh_pull_request(self, evt):
        self.bot.say('[%s] %s %s pull request #%d: %s (%s...%s): %s' % (
            Tags.UnderlinePink(evt.repo), self.format_nickname(evt.author),
            evt.action, evt.id, evt.title, Tags.Purple(evt.base_ref_name),
            Tags.Purple(evt.head_ref_name),
            Tags.UnderlineBlue(utils.shorten_url(evt.url))))

    def handle_gh_pull_request_comment(self, evt):
        self.bot.say('[%s] %s commented on #%s %s: %s' % (
            Tags.UnderlinePink(evt.repo), self.format_nickname(evt.author),
            evt.id, evt.hash[:6],
            Tags.UnderlineBlue(utils.shorten_url(evt.url))))

    def handle_gh_issue_comment(self, evt):
        self.bot.say('[%s] %s commented on #%s (%s): %s' % (
            Tags.UnderlinePink(evt.repo), self.format_nickname(evt.author),
            evt.id, evt.title, Tags.UnderlineBlue(utils.shorten_url(evt.url))))

    def handle_gh_commit_comment(self, evt):
        self.bot.say('[%s] %s commented on commit %s: %s' % (
            Tags.UnderlinePink(evt.repo), self.format_nickname(evt.author),
            evt.commit, Tags.UnderlineBlue(utils.shorten_url(evt.url))))

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
