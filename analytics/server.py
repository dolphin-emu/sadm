#! /usr/bin/env python3
# A simple stupid storage server which deserializes and writes reports to ElasticSearch.

import bottle
import elasticsearch
import struct
import time


def deserialize_varint(report, i):
    n = 0
    shift = 0
    while True:
        cont = report[i] & 0x80
        v = report[i] & 0x7F
        n |= (v << shift)
        shift += 7
        i += 1
        if not cont:
            break
    return n, i


def deserialize_with_tag(report, i, tag):
    if tag == 0:  # STRING
        length, i = deserialize_varint(report, i)
        val = report[i:i+length].decode("utf-8")
        i += length
    elif tag == 1:  # BOOL
        val = bool(report[i])
        i += 1
    elif tag == 2:  # UINT
        val, i = deserialize_varint(report, i)
    elif tag == 3:  # SINT
        positive = bool(report[i])
        i += 1
        val, i = deserialize_varint(report, i)
        if not positive:
            val = -val
    elif tag == 4:  # FLOAT
        val = struct.unpack("<f", report[i:i+4])[0]
        i += 4
    elif tag & 0x80:  # ARRAY
        length, i = deserialize_varint(report, i)
        val = []
        for j in range(length):
            v, i = deserialize_with_tag(report, i, tag & ~0x80)
            val.append(v)
    else:
        raise ValueError("Unknown tag %d" % tag)
    return val, i


def deserialize(report):
    if report[0] not in (0, 1):
        raise ValueError("Unknown wire format version %d" % report[0])
    values = []
    i = 1
    while i < len(report):
        tag = report[i]
        i += 1
        val, i = deserialize_with_tag(report, i, tag)
        values.append(val)
    data = {}
    i = 0
    while i < len(values):
        data[values[i]] = values[i + 1]
        i += 2
    return data


es = elasticsearch.Elasticsearch(['http://localhost:9200'])


@bottle.post("/report")
def do_report():
    report = bottle.request.body.read()
    data = deserialize(report)
    print(data)
    if 'type' not in data:
        return "KO"
    data['ts'] = int(time.time() * 1000)
    es.index(index='analytics', doc_type='event', body=data)
    return "OK"

if __name__ == "__main__":
    bottle.run(host="localhost", port=5007)
