import glob
import hashlib
import json
import os.path
import struct
import sys
import urllib2

SERVER_URL = 'http://richter.delroth.net:47981/'
#SERVER_URL = 'http://localhost:47981/'

class UnsupportedPlatformError(RuntimeError):
    pass

class NoCacheDirectoryError(RuntimeError):
    pass

def get_cache_directory():
    if sys.platform == 'win32':
        path = r'.\User\Cache'
    elif sys.platform.startswith('linux'):
        path = os.path.expanduser('~/.dolphin-emu/Cache')
    elif sys.platform == 'darwin':
        path = os.path.expanduser('~/Library/Application Support/Dolphin/Cache')
    else:
        raise UnsupportedPlatformError()

    if not os.path.exists(path):
        raise NoCacheDirectoryError()

    return path

def server():
    class ServerProxy(object):
        def __init__(self, base):
            self.base = base

        def remove_existing_hashes(self, hashes):
            hashes = json.dumps(hashes).encode('zlib')
            r = urllib2.urlopen(self.base + 'remove_existing_hashes', data=hashes)
            return json.loads(r.read().decode('zlib'))

        def send_new_data(self, data):
            data = json.dumps(data).encode('zlib')
            urllib2.urlopen(self.base + 'send_new_data', data=data).read()

    return ServerProxy(SERVER_URL)

class GameListItem(object):
    def __init__(self, fp):
        self._parse_from_file(fp)

    def get_data(self):
        return {
            'names': self.names,
            'wnames': self.wnames,
            'company': self.company,
            'description': self.description,
            'wdescription': self.wdescription,
            'unique_id': self.unique_id,
            'filesize': self.filesize,
            'volsize': self.volsize,
            'country': self.country,
            'compressed': self.compressed,
            'image': self.image,
            'platform': self.platform,
        }

    def _parse_from_file(self, fp):
        fp.seek(12)
        self.names = [self._read_string(fp) for i in xrange(6)]
        n_wnames = self._read_int(fp)
        self.wnames = [self._read_wstring(fp) for i in xrange(n_wnames)]
        self.company = self._read_string(fp)
        self.description = [self._read_string(fp) for i in xrange(6)]
        self.wdescription = self._read_wstring(fp)
        self.unique_id = self._read_string(fp)
        self.filesize = self._read_u64(fp)
        self.volsize = self._read_u64(fp)
        self.country = self._read_int(fp)
        self.compressed = self._read_u8(fp)
        self.image = self._read_u8_vect(fp)
        self.platform = self._read_int(fp)

    def _read_int(self, fp):
        return struct.unpack('<i', fp.read(4))[0]

    def _read_string(self, fp):
        size = self._read_int(fp)
        s = fp.read(size)
        return map(ord, s[:-1]) # no final \0

    def _read_u64(self, fp):
        return struct.unpack('<Q', fp.read(8))[0]

    def _read_u8(self, fp):
        return ord(fp.read(1))

    def _read_u8_vect(self, fp):
        size = self._read_int(fp)
        return list(ord(c) for c in fp.read(size))

    def _read_wstring(self, fp):
        size = self._read_int(fp)
        wchar_t_size = 2 if sys.platform == 'win32' else 4
        s = fp.read(size)[:-wchar_t_size]
        return s.decode('utf16') if sys.platform == 'win32' else s.decode('utf32')

def hash_game(gli):
    s = "%s%s%s" % (gli.names, gli.unique_id, gli.image)
    return hashlib.sha1(s).hexdigest()

def get_new_hashes(hashes):
    return server().remove_existing_hashes(hashes)

def send_new_data(data):
    return server().send_new_data(data)

if __name__ == '__main__':
    path = get_cache_directory()

    games = []
    for filename in glob.glob(os.path.join(path, "*.cache")):
        try:
            gli = GameListItem(open(filename, "rb"))
        except Exception:
            print "Failed to parse %s" % filename
            continue
        print "Parsed %s" % filename
        games.append(gli)

    hashes = {}
    for gli in games:
        hashes[hash_game(gli)] = gli

    print "Sending data to the server..."
    to_send = get_new_hashes(hashes.keys())
    send_new_data([hashes[h].get_data() for h in to_send])
