@public_component
def dl():
    install_nginx_service('dl', cat('dl.nginx'))
