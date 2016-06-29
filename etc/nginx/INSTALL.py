def install_nginx_service(name, contents):
    requires(nginx)
    install('/etc/nginx/services/%s.nginx' % name,
            contents=contents,
            owner='root:root',
            mode=0o644)
    defer(reload_nginx)


def reload_nginx():
    run('systemctl reload nginx')


@public_component
def nginx():
    apt_install('nginx')
    install('/etc/nginx/nginx.conf',
            contents=cat('nginx.conf'),
            owner='root:root',
            mode=0o644)
    install('/etc/nginx/services',
            directory=True,
            owner='root:root',
            mode=0o755)
    defer(reload_nginx)
