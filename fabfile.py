from fabric.api import *

import os.path

__all__ = ['buildbot']

env.user = 'root'
env.hosts = ['underlord.dolphin-emu.org']

def lcd_project(name):
    return lcd(os.path.join(os.path.dirname(env.real_fabfile), name))

def buildbot():
    with cd("/home/buildbot/sadm"), settings(sudo_user='buildbot'):
        sudo("git fetch origin master")
        sudo("git reset --hard origin/master")
    with cd("/home/buildbot/master"), settings(sudo_user='buildbot'):
        sudo("buildbot restart")
