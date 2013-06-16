from PIL import Image

import os.path
import pymongo
import sys

mongo = pymongo.MongoClient('mongodb1.alwaysdata.com')
db = mongo['dolphin-emu_bannercollect']
db.authenticate('dolphin-emu_bannercollect', 'nope')

for blob in db.blobs.find():
    uid = ''.join(map(chr, blob['unique_id']))
    uid += ' ' * (6 - len(uid))
    n = ''.join(map(chr, blob['names'][0]))
    encoding = 'cp932' if uid[3] == 'J' else 'iso-8859-15'
    try:
        n = n.decode(encoding).replace('/', '|').strip()
    except:
        n = '[decoding failed]'
    filename = os.path.join(sys.argv[1], "%s - %s.png" % (uid, n.encode('utf-8')))
    if os.path.exists(filename):
        continue
    print filename
    im = Image.new("RGBA", (96, 32))
    pix = im.load()
    data = iter(map(ord, blob['image']))
    for y in xrange(32):
        for x in xrange(96):
            pix[x, y] = (next(data), next(data), next(data), 255)
    im.save(filename)
