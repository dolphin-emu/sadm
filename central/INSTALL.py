@public_component
def central():
    install_nginx_service('central', cat('central.nginx'))
