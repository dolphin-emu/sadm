import logging
import requests
import xml.etree.ElementTree as ET

from config import cfg
import events
import utils


projects = set()


def sync_youtrack_projects():
    global projects
    response = requests.get('{youtrack}/rest/project/all'.format(
            youtrack=cfg.youtrack.base_url))
    tree = ET.fromstring(response.text)
    new_projects = set()
    for project in tree.findall('project'):
        new_projects.add(project.get('shortName'))
    if new_projects != projects:
        logging.info('YouTrack projects updated: added {}, removed {}'.format(
                new_projects.difference(projects),
                projects.difference(new_projects)))
    projects = new_projects


def start():
    utils.spawn_periodic_task(cfg.youtrack.projects_refresh_interval,
                              sync_youtrack_projects)
