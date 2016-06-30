@public_component
def symbols():
    install_nginx_service('symbols', cat('symbols.nginx'))
