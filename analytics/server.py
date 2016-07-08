#! /usr/bin/env python3
# A simple stupid storage server which deserializes and writes reports to PGSQL.

import bottle
import psycopg2
import psycopg2.extras
import struct


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


def deserialize(report):
    if report[0] != 0:
        raise ValueError("Unknown wire format version %d" % report[0])
    values = []
    i = 1
    while i < len(report):
        tag = report[i]
        i += 1
        if tag == 0:  # STRING
            length, i = deserialize_varint(report, i)
            values.append(report[i:i+length].decode("utf-8"))
            i += length
        elif tag == 1:  # BOOL
            values.append(bool(report[i]))
            i += 1
        elif tag == 2:  # UINT
            v, i = deserialize_varint(report, i)
            values.append(v)
        elif tag == 3:  # SINT
            positive = bool(report[i])
            i += 1
            v, i = deserialize_varint(report, i)
            values.append(v if positive else -v)
        elif tag == 4:  # FLOAT
            values.append(struct.unpack("<f", report[i:i+4])[0])
            i += 4
        else:
            raise ValueError("Unknown tag %d" % tag)
    data = {}
    i = 0
    while i < len(values):
        data[values[i]] = values[i + 1]
        i += 2
    return data


DB = psycopg2.connect("dbname=analytics")


@bottle.post("/report")
def do_report():
    report = bottle.request.body.read()
    data = deserialize(report)
    print(data)
    cur = DB.cursor()
    cur.execute("INSERT INTO store(report) VALUES(%s)", [psycopg2.extras.Json(data)])
    DB.commit()
    cur.close()
    return "OK"

if __name__ == "__main__":
    bottle.run(host="localhost", port=5007)
