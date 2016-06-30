@public_component
def analytics():
    install_nginx_service('analytics', cat('analytics.nginx'))
