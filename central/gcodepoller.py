"""Generates GCodeIssueEvent objects by polling the Google Code issues Atom
feed (URL specified in the configuration).
"""

from config import cfg

import events
import feedparser
import logging
import re
import time
import utils


NEW_ISSUE_RE = re.compile(r'^Issue (\d+) created: "(.*?)"$')
UPDATED_ISSUE_RE = re.compile(r'^Update (\d+) to issue (\d+) \("(.*?)"\)$')


class Poller:
    def __init__(self, cfg):
        self.cfg = cfg

    def run(self):
        self.last_update = None
        while True:
            d = feedparser.parse(self.cfg.atom_feed)
            if self.last_update != d.feed.updated_parsed and \
                    self.last_update is not None:
                logging.info('Atom feed updated, finding new items.')
                for entry in d.entries:
                    if entry.updated_parsed > self.last_update:
                        logging.info('New entry found: %r' % entry.title)
                        url = entry.link

                        new_match = NEW_ISSUE_RE.match(entry.title)
                        updated_match = UPDATED_ISSUE_RE.match(entry.title)
                        if new_match:
                            issue, title = new_match.groups()
                            issue = int(issue)
                            update = None
                        elif updated_match:
                            update, issue, title = updated_match.groups()
                            update, issue = int(update), int(issue)
                        else:
                            logging.error('New entry does not match any RE!')
                            continue

                        evt = events.GCodeIssue(update is None, update, issue,
                                                title, entry.author,
                                                entry.link)
                        events.dispatcher.dispatch('gcode', evt)

            self.last_update = d.feed.updated_parsed
            time.sleep(self.cfg.refresh_interval)

def start():
    """Starts the GCode issue poller."""
    url = cfg.gcode.atom_feed
    logging.info('Starting GCode issue polling on %r', url)

    poller = Poller(cfg.gcode)
    utils.DaemonThread(target=poller.run).start()
