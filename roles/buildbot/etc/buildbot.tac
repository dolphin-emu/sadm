import os
import sys

from twisted.application import service
from buildbot.master import BuildMaster

basedir = os.getcwd()
configfile = os.path.join(os.path.dirname(__file__), 'master.cfg')

# Default umask for server
umask = None

# note: this line is matched against to check that this is a buildmaster
# directory; do not edit it.
application = service.Application('buildmaster')
from twisted.python.log import ILogObserver, FileLogObserver
application.setComponent(ILogObserver, FileLogObserver(sys.stderr).emit)

m = BuildMaster(basedir, configfile, umask)
m.setServiceParent(application)
