"""Web server module that received events from WebHooks and user interactions
and shows a list of recent events."""

from config import cfg

import logging

def start():
    """Starts the web server."""
    port = cfg.web.port

    logging.info('Starting web server: port=%d' % port)
