#! /usr/bin/env python3
"""
install.py -- Dolphin SADM installer.

Think of it as Makefiles written in Python. Files called "INSTALL.py" anywhere
in the repository are loaded by this script to find possible actions (declared
as functions).
"""

import argparse
import collections
import functools
import getpass
import pathlib
import shutil
import subprocess
import sys
import textwrap

try:
    import paramiko
except ImportError:
    paramiko = None

MAIN_REPO = 'https://github.com/dolphin-emu/sadm'

Component = collections.namedtuple('Component', 'name func doc')


class State:
    def __init__(self, parent=None):
        self.parent = parent

    def __getattr__(self, name):
        if name in self.__dict__:
            return self.__dict__['name']
        if self.parent is None:
            raise AttributeError('No attribute %r in state.' % name)
        return getattr(self.parent, name)


state = State()
deferred_handlers = []


def builtin_path(p):
    return pathlib.Path(p)


def builtin_public_component(func):
    """Public components are exposed through CLI."""
    func.is_public_component = True
    return func


def builtin_utility(func):
    """Utility functions can be called from other modules without resetting
    context-dependent attributes (e.g. the source path)."""
    func.is_utility = True
    return func


def builtin_print(*args, **kwargs):
    return print(*args, **kwargs)


def builtin_pwd():
    try:
        return state.pwd
    except AttributeError:
        # Default to source directory.
        return state.source_dir


def builtin_source_dir():
    return state.source_dir


def builtin_run(cmd, stdin='', capture=False):
    shell = isinstance(cmd, str)
    stdout = subprocess.PIPE if capture else None
    stderr = subprocess.PIPE if capture else None
    if not capture:
        print('[+] Running: %s' % cmd)
    popen = subprocess.Popen(cmd,
                             shell=shell,
                             cwd=str(builtin_pwd()),
                             stdin=subprocess.PIPE,
                             stdout=stdout,
                             stderr=stderr)
    return popen.communicate(stdin)


builtin_chown = shutil.chown


def builtin_defer(func, *args, **kwargs):
    """Enqueues an action to run after everything has been processed."""
    deferred_handlers.append(functools.partial(func, *args, **kwargs))


def state_decorator(f):
    @functools.wraps(f)
    def wrapper(*args, **kwargs):
        global state
        state = State(state)
        try:
            return f(*args, **kwargs)
        finally:
            state = state.parent

    return wrapper


def source_dir_decorator(install_file):
    def decorator(f):
        @functools.wraps(f)
        def wrapper(*args, **kwargs):
            global state
            state.source_dir = install_file.parent
            return f(*args, **kwargs)

        return wrapper

    return decorator


def repo_path():
    return pathlib.Path('.')


def enumerate_install_files():
    return repo_path().glob('**/INSTALL.py')


def get_new_config_namespace():
    return {name[len('builtin_'):]: func
            for (name, func) in globals().items()
            if callable(func) and name.startswith('builtin_')}


def postprocess_install_function(install_file, func):
    decorators = [functools.lru_cache(maxsize=None)]
    if not getattr(func, 'is_utility', False):
        decorators.append(source_dir_decorator(install_file))
    decorators.append(state_decorator)
    for decorator in decorators:
        func = decorator(func)
    return func


def load_all_actions():
    namespace = get_new_config_namespace()
    builtins = set(namespace.keys())
    what_defined_where = {}  # Name -> (object, install file).
    for install_file in enumerate_install_files():
        with install_file.open() as f:
            code = compile(f.read(), str(install_file), 'exec')
            exec(code, namespace, namespace)

            # Try to find redefinitions (which should not happen).
            for name, (rule, original_install) in what_defined_where.items():
                if namespace.get(name, rule) is not rule:
                    raise RuntimeError(
                        'Rule %r (defined in %s) redefined by %s' %
                        (name, original_install, install_file))

            # Process the namespace in place. This is required for __globals__
            # in each function to point to the postprocessed version.
            for name, rule in namespace.items():
                if name not in what_defined_where and name not in builtins:
                    if callable(rule):
                        rule = namespace[name] = postprocess_install_function(
                            install_file, rule)
                    what_defined_where[name] = (rule, install_file)
    return namespace


def get_components(actions):
    for name, action in actions.items():
        if not getattr(action, 'is_public_component', False):
            continue
        yield Component(name, action, action.__doc__)


def run_action(actions, func):
    actions['__to_run'] = func
    exec('__to_run()', actions, actions)


def tree_is_clean():
    if (repo_path() / '.git').is_dir():
        out = subprocess.run(['git', 'status', '--porcelain'],
                             stdout=subprocess.PIPE)
        return out.returncode == 0 and out.stdout == b''
    return True


def ssh_connect(host):
    client = paramiko.SSHClient()
    client.load_system_host_keys()
    client.set_missing_host_key_policy(paramiko.WarningPolicy())
    try:
        client.connect(host, username='root')
    except paramiko.ssh_exception.PasswordRequiredException:
        client.connect(host, username='root', password=getpass.getpass())
    return client


def ssh_run(remote, command, data=b''):
    stdin, stdout, stderr = remote.exec_command(command)
    stdin.write(data)
    stdin.channel.shutdown_write()
    stdin.close()
    return stdout.read(), stderr.read()


def ssh_interactive(chan):
    """Stolen from paramiko.demos.interactive."""
    import select
    import socket
    import termios
    import tty

    oldtty = termios.tcgetattr(sys.stdin)
    try:
        tty.setraw(sys.stdin.fileno())
        tty.setcbreak(sys.stdin.fileno())
        chan.settimeout(0.0)

        while True:
            r, w, e = select.select([chan, sys.stdin], [], [])
            if chan in r:
                try:
                    x = chan.recv(1024).decode('utf-8')
                    if len(x) == 0:
                        sys.stdout.write('\r\n*** EOF\r\n')
                        break
                    sys.stdout.write(x)
                    sys.stdout.flush()
                except socket.timeout:
                    pass
            if sys.stdin in r:
                x = sys.stdin.read(1)
                if len(x) == 0:
                    break
                chan.send(x)

    finally:
        termios.tcsetattr(sys.stdin, termios.TCSADRAIN, oldtty)


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--local_config',
                        action='store_true',
                        help='Deploys local modifications instead of HEAD.')
    parser.add_argument('--host', help='Host to deploy against.')
    parser.add_argument('--deploy_here',
                        action='store_true',
                        help='Deploy on the machine running this script.')
    parser.add_argument('--list', action='store_true', help='List components.')
    parser.add_argument('component', nargs='*', help='Components to deploy.')
    args = parser.parse_args()

    actions = load_all_actions()
    if args.list:
        wrapper = textwrap.TextWrapper(initial_indent='\t')
        for component in sorted(get_components(actions)):
            doc = component.doc or 'Undocumented.'
            print(' - %r:\n%s' % (component.name, wrapper.fill(doc)))
        sys.exit(0)

    if args.host:
        if paramiko is None:
            raise ImportError("Please install the Python 'paramiko' module.")
        remote = ssh_connect(args.host)
        tmpdir, _= ssh_run(remote, 'mktemp -td sadm_install.XXXXXXXX')
        tmpdir = tmpdir.rstrip()
        try:
            ssh_run(remote, b'cd %s && git clone %s repo' %
                    (tmpdir, MAIN_REPO.encode('utf-8')))
            if args.local_config:
                head, _ = ssh_run(remote,
                                  b'cd %s/repo && git rev-parse HEAD' % tmpdir)
                out = subprocess.run(['git', 'diff', head.rstrip()],
                                     stdout=subprocess.PIPE)
                if out.returncode != 0:
                    raise RuntimeError('git diff returned %d' % out.returncode)
                ssh_run(remote, b'cd %s/repo && patch -Np1' % tmpdir,
                        out.stdout)
            chan = remote.invoke_shell()
            chan.send(
                b'cd %s/repo && exec python3 install.py %s --deploy_here %s\n'
                % (tmpdir, b'--local_config' if args.local_config else b'',
                   b' '.join(s.encode('utf-8') for s in args.component)))
            ssh_interactive(chan)
        finally:
            ssh_run(remote, b'rm -rf %s' % tmpdir)
        sys.exit(0)

    if args.deploy_here:
        if not tree_is_clean() and not args.local_config:
            raise RuntimeError(
                'Local deployment requested, but tree is unclean. '
                'Do you need --local_config?')

        for component in args.component:
            if component not in set(c.name for c in get_components(actions)):
                raise ValueError('%r is not a component. Use --list.' %
                                 component)
        for component in args.component:
            run_action(actions, actions[component])
        for action in deferred_handlers:
            run_action(actions, action)
        sys.exit(0)
