#! /usr/bin/env python3
# Processes serialized events from users and dual-writes them to ElasticSearch
# and ClickHouse.

import bottle
import collections
import clickhouse_driver
import datetime
import elasticsearch
import enum
import re
import struct
import time

from collections.abc import Mapping
from typing import Any


# Represents the type of an analytics event field.
ScalarDataType = enum.Enum('ScalarDataType', 'STRING BOOL UINT SINT FLOAT')
DataType = collections.namedtuple('DataType', 'scalar_type is_array')

# Allowed field names.
ALLOWED_FIELD_NAME_RE = re.compile(r'^[a-zA-Z0-9_-]+$')

# Interface to ClickHouse: maintains not only the client connection to the
# database, but also a cache of the event table schema so we can support some
# rough form of dynamic schema updating.
class ClickHouseInterface:
    def __init__(self, *args, **kwargs):
        self.client = clickhouse_driver.Client(*args, **kwargs)

        self.columns = set()
        for (name, _, _, _, _) in self.client.execute('DESCRIBE TABLE event'):
            self.columns.add(name)

    def add_column(self, name: str, ftype: DataType):
        mapping = {
            ScalarDataType.STRING: 'String',
            ScalarDataType.BOOL: 'UInt8',
            ScalarDataType.UINT: 'UInt64',
            ScalarDataType.SINT: 'Int64',
            ScalarDataType.FLOAT: 'Float32',
        }
        chtype = mapping[ftype.scalar_type]
        if ftype.is_array:
            chtype = f'Array({chtype})'
        else:
            chtype = f'Nullable({chtype})'

        print(f'Adding new ClickHouse column: {name}, type {ftype} -> {chtype}')
        self.client.execute(f'ALTER TABLE event ADD COLUMN `{name}` {chtype}')

        self.columns.add(name)

    def insert_event(self, data: Mapping[str, tuple[Any, DataType]]):
        # Check whether we need to add new columns before inserting data.
        for name, (_, ftype) in data.items():
            if name not in self.columns:
                self.add_column(name, ftype)

        # Generate columns names list for the SQL statement.
        columns = ','.join(f'`{name}`' for name in data.keys())

        # Drop types.
        data = {k: v[0] for k, v in data.items()}

        self.client.execute(f'INSERT INTO event ({columns}) VALUES',
                            [data])


def deserialize_varint(report: bytes, i: int) -> tuple[int, int]:
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


def deserialize_with_tag(report: bytes, i: int, tag: int) -> tuple[DataType, Any, int]:
    if tag == 0:  # STRING
        ftype = DataType(scalar_type=ScalarDataType.STRING, is_array=False)
        length, i = deserialize_varint(report, i)
        val = report[i:i+length].decode("utf-8")
        i += length
    elif tag == 1:  # BOOL
        ftype = DataType(scalar_type=ScalarDataType.BOOL, is_array=False)
        val = bool(report[i])
        i += 1
    elif tag == 2:  # UINT
        ftype = DataType(scalar_type=ScalarDataType.UINT, is_array=False)
        val, i = deserialize_varint(report, i)
    elif tag == 3:  # SINT
        ftype = DataType(scalar_type=ScalarDataType.SINT, is_array=False)
        positive = bool(report[i])
        i += 1
        val, i = deserialize_varint(report, i)
        if not positive:
            val = -val
    elif tag == 4:  # FLOAT
        ftype = DataType(scalar_type=ScalarDataType.FLOAT, is_array=False)
        val = struct.unpack("<f", report[i:i+4])[0]
        i += 4
    elif tag & 0x80:  # ARRAY
        length, i = deserialize_varint(report, i)
        val = []
        for j in range(length):
            ftype, v, i = deserialize_with_tag(report, i, tag & ~0x80)
            val.append(v)
        ftype = DataType(scalar_type=ftype.scalar_type, is_array=True)
    else:
        raise ValueError("Unknown tag %d" % tag)
    return ftype, val, i


def deserialize(report: bytes) -> Mapping[str, tuple[Any, DataType]]:
    if report[0] not in (0, 1):
        raise ValueError("Unknown wire format version %d" % report[0])
    values = []
    i = 1
    while i < len(report):
        tag = report[i]
        i += 1
        ftype, val, i = deserialize_with_tag(report, i, tag)
        values.append((val, ftype))
    data = {}
    i = 0
    while i < len(values):
        assert ALLOWED_FIELD_NAME_RE.match(values[i][0]) is not None
        data[values[i][0]] = values[i + 1]
        i += 2
    return data


es = elasticsearch.Elasticsearch(['http://localhost:9200'])

def write_to_elasticsearch(data: Mapping[str, tuple[Any, DataType]]):
    data = {k: v[0] for k, v in data.items()}
    data['ts'] = int(time.time() * 1000)
    es.index(index='analytics', doc_type='event', body=data)


ch = ClickHouseInterface(host='localhost')

def write_to_clickhouse(data: Mapping[str, Any]):
    # Add timestamp and date partitioning info. Types don't matter since these
    # columns always exist.
    data['ts'] = (datetime.datetime.now(), None)
    data['date'] = (datetime.date.today(), None)
    ch.insert_event(data)


@bottle.post("/report")
def do_report():
    report = bottle.request.body.read()

    data = deserialize(report)
    print(data)

    if 'type' not in data:
        return "KO"

    write_to_elasticsearch(data.copy())
    write_to_clickhouse(data)

    return "OK"

if __name__ == "__main__":
    bottle.run(host="localhost", port=5007)
