#! /usr/bin/env python3
#
# killswitch.py - Hals the VM when no builds are pending for > N minutes.

import logging
import logging.handlers
import os
import requests
import sys
import time
import yaml


def setup_logging(program, verbose=False, local=True):
    """Sets up the default Python logger.

    Always log to syslog, optionaly log to stdout.

    Args:
      program: Name of the program logging informations.
      verbose: If true, log more messages (DEBUG instead of INFO).
      local: If true, log to stdout as well as syslog.
    """
    loggers = []
    if sys.platform.startswith('linux'):
        loggers.append(logging.handlers.SysLogHandler('/dev/log'))
    if local:
        loggers.append(logging.StreamHandler())
    for logger in loggers:
        logger.setFormatter(logging.Formatter(
            program + ': [%(levelname)s] %(message)s'
        ))
        logging.getLogger('').addHandler(logger)
    logging.getLogger('').setLevel(logging.DEBUG if verbose else logging.INFO)


if __name__ == '__main__':
    setup_logging('killswitch')

    cfg_file = '/etc/killswitch.yml'
    if len(sys.argv) > 1:
        cfg_file = sys.argv[1]
    CFG = yaml.load(open(cfg_file))
    n_without_pending = 0
    while True:
        try:
            pending = 0
            building = 0
            for url in CFG['url']:
                data = requests.get(url).json()
                pending += data.get('pendingBuilds', 0)
                building += len(data.get('currentBuilds', []))
            if not pending and not building:
                logging.warning('No tasks pending, currently at %d',
                                n_without_pending)
                n_without_pending += 1
            else:
                logging.warning('%d builds pending, %d builds running...',
                        pending, building)
                n_without_pending = 0
        except Exception:
            logging.exception('Could not fetch current queue status')
            n_without_pending += 1

        if n_without_pending > CFG.get('threshold', 10):
            os.system(CFG.get('shutdown_command', '/sbin/halt'))

        time.sleep(CFG.get('interval', 10))
