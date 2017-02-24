@public_component
def buildbot():
    install_nginx_service('buildbot', cat('buildbot.nginx'))
