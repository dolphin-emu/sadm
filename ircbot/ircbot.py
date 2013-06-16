"""
Copyright 2011 Shawn Hoffman

Recieves JSON messages from googlecode and outputs to IRC channels.
Polls googlecode Atom feeds and lists updates.
"""
from twisted.words.protocols import irc
from twisted.internet import protocol
from twisted.internet.task import LoopingCall
from twisted.application.internet import TCPServer, TCPClient
from twisted.application.service import Application
from twisted.web.resource import Resource
from twisted.web.server import Site
from twisted.python import log

import gdata.projecthosting.client
import gdata.projecthosting.data
import gdata.gauth
import gdata.client
import gdata.data
import atom.http_core
import atom.core

import hmac, json, datetime, rfc3339, re
import requests


'''IRC text colors'''
color_begin = "\x03"
color_end = "\x0f"
color_normal = color_end
color_f_white = color_begin + "00"
color_f_black = color_begin + "01"
color_f_navy = color_begin + "02"
color_f_green = color_begin + "03"
color_f_red = color_begin + "04"
color_f_brown = color_begin + "05"
color_f_purple = color_begin + "06"
color_f_orange = color_begin + "07"
color_f_yellow = color_begin + "08"
color_f_lime = color_begin + "09"
# Must be used directly after a color_f_*
color_b_teal = ",10"
color_b_aqua = ",11"
color_b_royal = ",12"
color_b_pink = ",13"
color_b_grey = ",14"
color_b_silver = ",15"


def shorten(url):
    try:
        return requests.get('http://ln-s.net/home/api.jsp', params={"url": url}).text.split(' ')[1].split('\n')[0]
    except:
        return "<fail>"


class ProjectHostingClientBasic(gdata.projecthosting.client.ProjectHostingClient):
    '''Overrides the default API path'''
    def __init__(self, type_uri, path_option = ''):
        self.ISSUES_FULL_FEED = '/feeds/p/%s/' + type_uri + '/basic' + path_option
        gdata.projecthosting.client.ProjectHostingClient.__init__(self)
        
    def BestEffortConverter(self, response):
        '''Laziness knows no bounds'''
        resp = response.read()
        target_class = gdata.projecthosting.data.IssuesFeed
        try:
            return atom.core.parse(resp, target_class)
        except:
            return atom.core.parse(unicode(resp, errors='ignore'), target_class)
            
    def get_issues(self, project_name,
        desired_class=gdata.projecthosting.data.IssuesFeed, **kwargs):
        try:
            return self.get_feed(self.ISSUES_FULL_FEED %
                project_name, desired_class=desired_class,
                converter=self.BestEffortConverter, **kwargs)
        except:
            return None

'''Easy to use feedreaders!'''
class IssueUpdateFeed(ProjectHostingClientBasic):
    def __init__(self):
        ProjectHostingClientBasic.__init__(self, 'issueupdates')


class SVNChangesFeed(ProjectHostingClientBasic):
    def __init__(self):
        ProjectHostingClientBasic.__init__(self, 'svnchanges')


class SVNChangesSpecificFeed(ProjectHostingClientBasic):
    def __init__(self, path):
        ProjectHostingClientBasic.__init__(self, 'svnchanges', '?path=' + path)


class DownloadsFeed(ProjectHostingClientBasic):
    def __init__(self):
        ProjectHostingClientBasic.__init__(self, 'downloads')


class UpdatesFeed(ProjectHostingClientBasic):
    def __init__(self):
        ProjectHostingClientBasic.__init__(self, 'updates')


class CHookBot(irc.IRCClient):
    """Commit Hook Bot"""
	
    def __init__(self):
        self.nickname = "irrawaddy"
        self.lineRate = .8
        
        self.last_msg = "No logs since starting"
        self.last_issue_update = None
        
        self.issue_timer = LoopingCall(self.issue_lister_cb)
    
    def connectionMade(self):
        irc.IRCClient.connectionMade(self)
        self.factory.bot = self

    def connectionLost(self, reason):
        irc.IRCClient.connectionLost(self, reason)
        self.issue_timer.stop()

    def signedOn(self):
        """Called when bot has succesfully signed on to server."""
        self.join(self.factory.channel)
        
    def joined(self, channel):
        """This will get called when the bot joins the channel."""
        self.issue_timer.start(1 * 60) # 1 minutes * 60 seconds
        
    def privmsg(self, user, channel, msg):
        """This will get called when the bot receives a message."""
        user = user.split('!', 1)[0]
        
        if channel == self.nickname:
            self.handle_query(user, msg)
        elif msg.startswith("!lastlog"):
            self.send_last_msg(channel)
        elif msg.startswith("!branch "):
            branch = msg.split(' ')[1]
            txt = u"Source code for branch %s%s%s: %s%s%s builds URL: %s%s%s" % (
                        color_f_green, branch, color_normal,
                        color_f_navy, shorten("https://code.google.com/p/dolphin-emu/source/list?name=" + branch), color_normal,
                        color_f_navy, shorten("http://dolphin-emu.org/download/list/%s/1/" % branch), color_normal
            )
            self.msg(channel, txt.encode('utf-8'))
        ''' TODO
        elif msg.startswith("!issues"):
            self.send_issues_dated(channel)
        '''
        # Always log for myself :)
        if "shuffle" in msg:
            log.msg(msg)
        
        if self.nickname in msg:
            self.msg(self.factory.channel, "WARK WARK WARK")
        
    def handle_query(self, user, msg):
        if "lastlog" in msg:
            self.send_last_msg(user)
        ''' TODO
        if "issues" in msg:
            try:
                hours = int(re.search("(\d+)", msg).group(1)) # poor man's parsing
            except AttributeError:
                hours = 1
            self.send_issues_dated(user, True, hours)
        '''
        if "help" in msg:
            self.send_help(user)
            
    def send_help(self, user):
        self.msg(user, "Supported commands: (prefix with ! if in channel)")
        self.msg(user, "lastlog    Display last commit log")
        '''
        self.msg(user, "issues X   Display issues from the last hour (say in query to define X hours)")
        '''
    def send_last_msg(self, recipient):
        self.msg(recipient, self.last_msg)
        
    def send_issue_details(self, issue, recipient):
        issue_id = issue.id.text.split('/')[-1]
        comments = self.issue_client.get_issue_comments(issue_id).entry
        num_comments = len(comments)
        
        if num_comments == 0:
            author = self.issue_client.get_author_from_atom(issue)
            self.msg(recipient,
                "Last change was issue creation by " + color_f_green +
                    author + color_normal)
        else:
            author = self.issue_client.get_author_from_atom(
                comments[num_comments-1])
            self.msg(recipient,
                "Last change was posting of comment #%s by %s" % \
                    (num_comments, color_f_green + author + color_normal))
        
    def send_issues_dated(self, recipient, send_details = True, hours = 1):
        then = datetime.datetime.now() - datetime.timedelta(hours = hours)
        feed = self.issue_client.get_issues_dated(then)
        for issue in feed.entry:
            issue_id = issue.id.text.split('/')[-1]
            issue_fmtd = u"%s |%s| %s" % (
                self.issue_client.get_issue_link(issue_id),
                issue.status.text,
                issue.title.text)
            self.msg(recipient, issue_fmtd.encode("utf-8"))
                
            if send_details:
                self.send_issue_details(issue, recipient)
                
    def issue_lister_cb(self):
        # Send issues updated in the last hour to the main channel w/o details
        if self.last_issue_update is None:
            self.last_issue_update = rfc3339.now()
        feed = IssueUpdateFeed().get_issues('dolphin-emu')
        if feed is None:
            log.msg("Unable to get feed")
            return
        for i in reversed(feed.entry):
            issue_date = rfc3339.parse_datetime(i.updated.text)
            if issue_date > self.last_issue_update:
                self.last_issue_update = issue_date
                issue_fmtd = u"%s %s %s" % (
                    i.title.text,
                    color_f_green + i.author[0].name.text + color_normal,
                    i.link[0].href)
                self.msg(self.factory.channel, issue_fmtd.encode("utf-8"))
        #self.send_issues_dated(self.factory.channel, False, 1)
                        
    def commit_msg(self, msg):
        self.last_msg = msg
        self.send_last_msg(self.factory.channel)


class CHookBotFactory(protocol.ClientFactory):
    """A factory for CHookBots."""
	
    # the class of the protocol to build when new connection is made
    protocol = CHookBot

    def __init__(self, channel):
        self.channel = channel

    def clientConnectionLost(self, connector, reason):
        """If we get disconnected, reconnect to server."""
        connector.connect()

    def clientConnectionFailed(self, connector, reason):
        log.msg(reason)
        reactor.stop()

        
class PostPage(Resource):
    def __init__(self, botf, secret_key):
        self.bot_factory = botf
        self.secret_key = secret_key
        
    def render_GET(self, request):
        return ''

    def render_POST(self, request):
        # Check authentication
        m = hmac.new(self.secret_key)
        m.update(request.content.getvalue())
        digest = m.hexdigest()
        try:
            hdr_digest = request.received_headers["google-code-project-hosting-hook-hmac"]
        except KeyError:
            hdr_digest = "0"

        if digest != hdr_digest:
            log.msg("failed auth check")
            # return 200 so the msg is not resent
            return ''
        
        # Parse JSON
        payload = json.loads(request.content.getvalue())
        
        # Send to IRC
        for revision in payload["revisions"][:5]:
            msg = revision["message"].split("\n")[0]
            txt = u"%s by %s [%s|%s|%s] %s %s" % ( \
                revision["revision"][:7],
                color_f_green + revision["author"] + color_normal,
                color_f_lime + str(len(revision["added"])) + color_normal,
                color_f_orange + str(len(revision["modified"])) + color_normal,
                color_f_red + str(len(revision["removed"])) + color_normal,
                color_f_navy + shorten("https://code.google.com/p/dolphin-emu/source/detail?r=" + revision["revision"]) + color_normal,
                msg)
            self.bot_factory.bot.commit_msg(txt.encode('utf-8'))
        if len(payload["revisions"]) > 5:
            msg = u"... and %d more commits (not displayed)" % (len(payload["revisions"]) - 5)
            self.bot_factory.bot.commit_msg(msg.encode("utf-8"))
        return ''

            
'''
All config can be done here (except for bot nick...)
TODO more rubust config...
'''
# The application for twistd            
application = Application("gcode-irc-bot")

# Setup IRC bot
PROJECT_NAME = 'dolphin-dev'
botf = CHookBotFactory('#' + PROJECT_NAME)

# Setup HTTP listener
root = Resource()
root.putChild('dolphin-emu', PostPage(botf, open('gcode-password.txt').read().strip()))

# Start!
TCPServer(8800, Site(root)).setServiceParent(application)
TCPClient("irc.freenode.net", 6667, botf).setServiceParent(application)
