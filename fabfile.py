from fabric.api import *

import os.path

__all__ = ['buildbot']

env.user = 'root'
env.hosts = ['underlord.dolphin-emu.org']

def lcd_project(name):
    return lcd(os.path.join(os.path.dirname(env.real_fabfile), name))

def buildbot():
    with cd("/home/buildbot/master"), lcd_project('buildbot'), \
         settings(sudo_user='buildbot'):
        put('master.cfg', 'master.cfg')
        sudo("buildbot restart")
