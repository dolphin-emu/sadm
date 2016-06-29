@utility
def cat(path, bytes=True):
    p = (source_dir() / path)
    if bytes:
        return p.read_bytes()
    else:
        return p.read_text()


@utility
def install(dest, contents=None, directory=False, owner=None, mode=None):
    if owner is None or mode is None:
        raise RuntimeError('%s: No owner or mode provided.' % dest)
    if not directory and contents is None:
        raise RuntimeError('%s: No contents provided.')
    p = pwd() / path(dest)
    print('[+] Installing: %s' % p)
    if directory:
        p.mkdir(mode=mode, parents=True, exist_ok=True)
    else:
        p.write_bytes(contents)
        p.chmod(mode)
    user, group = owner.split(':')
    chown(str(p), user, group)


def apt_update():
    run(['apt-get', 'update'])


def apt_install(package):
    apt_update()
    run(['apt-get', 'install', '-y', package])


def requires(*args):
    for action in args:
        action()
