import boto.ec2
import datetime
import re
import requests
import sys
import time
import yaml


def median(l):
    l = list(l)
    half = len(l) // 2
    l.sort()
    if len(l) % 2 == 0:
        return (l[half - 1] + l[half]) / 2
    else:
        return l[half]


def avg(l):
    l = list(l)
    return sum(l) / len(l)


class Spawner(object):
    def __init__(self, cfg, ec2, buildbot_cfg):
        self.cfg = cfg
        self.ec2 = ec2
        self.buildbot_cfg = buildbot_cfg
        self.last_empty_time = 0

    def log(self, msg, *args):
        print(self.cfg['name'] + ': ' + (msg % args))

    def get_queue_length(self):
        pending = 0
        for builder in self.cfg['builders']:
            try:
                url = self.buildbot_cfg['url'] + '/json/builders/' + builder
                data = requests.get(url).json()
                pending += data.get('pendingBuilds', 0)
            except Exception as e:
                self.log('Error while fetching builder %s: %s', builder, e)
        return pending

    def cancel_spot_request(self, reqid):
        self.ec2.cancel_spot_instance_requests([reqid])

    def has_unfulfilled_spot_request(self):
        filters = {'launch.image-id': self.cfg['ami']}
        results = self.ec2.get_all_spot_instance_requests(filters=filters)
        for r in results:
            if r.state in ['open', 'active']:
                ts = datetime.datetime(*map(int,
                    re.split('[^\d]', r.create_time)[:-1]))
                delta = (datetime.datetime.utcnow() - ts).total_seconds()
                if r.status.code == 'price-too-low' and delta > 1800:
                    self.log('Request %s started at %s and in price-too-low '
                             '(price=%f). Restarting.', r.id, r.create_time,
                             r.price)
                    self.cancel_spot_request(r.id)
                return True
        return False

    def get_spot_price(self):
        timestamp_from = datetime.datetime.utcnow()
        history = self.ec2.get_spot_price_history(
                instance_type=self.cfg['type'],
                product_description=self.cfg['product'],
                max_results=100)
        per_az_history = {}
        for record in history:
            az_data = per_az_history.setdefault(record.availability_zone, [])
            ts = datetime.datetime(*map(int,
                re.split('[^\d]', record.timestamp)[:-1]))
            ts -= datetime.datetime.utcnow()
            az_data.append({'tsdelta': ts.total_seconds(),
                            'price': record.price})
        per_az_med = {az: median(r['price'] for r in per_az_history[az])
                      for az in per_az_history}
        max_az = max(per_az_med.items(), key=lambda r: r[1])[0]
        recent_history = [r['price'] for r in per_az_history[max_az]
                          if r['tsdelta'] > -3600 * 4]
        if not recent_history:
            recent_history = [r['price'] for r in per_az_history[max_az]][:20]
        proposed_price = max(recent_history) * 0.99995
        if proposed_price > median(recent_history) * 1.05:
            proposed_price = median(recent_history) * 1.05
        return proposed_price

    def create_spot_request(self):
        price = self.get_spot_price()
        self.log('Spot price: $%.5f', price)
        self.ec2.request_spot_instances(price, self.cfg['ami'],
                key_name=self.cfg['keypair'],
                security_group_ids=[self.cfg['security_group']],
                instance_type=self.cfg['type'])

    def update(self):
        self.log('Starting update')
        qlength = self.get_queue_length()
        self.log('Queue length: %.2f', qlength)
        if qlength == 0:
            self.last_empty_time = time.time()
            return
        if self.has_unfulfilled_spot_request():
            self.log('Unfulfilled spot requests found, not doing anything')
            # TODO: Potentially increase price.
            return
        if qlength >= self.cfg['max_queue_size'] or \
            time.time() - self.last_empty_time >= self.cfg['max_latency']:
            self.log('Creating a new spot request')
            self.create_spot_request()
            self.last_empty_time = time.time()
        else:
            self.log('QSize < %d and still %d seconds to go',
                    self.cfg['max_queue_size'],
                    self.cfg['max_latency'] + self.last_empty_time
                        - time.time())

if __name__ == '__main__':
    cfg_file = sys.argv[1]
    CFG = yaml.load(open(cfg_file))

    ec2 = boto.ec2.connect_to_region(
            CFG['ec2']['region'],
            aws_access_key_id=CFG['ec2']['access_key_id'],
            aws_secret_access_key=CFG['ec2']['secret_access_key'])

    spawners = [Spawner(cfg, ec2, CFG['buildbot']) for cfg in CFG['spawners']]
    while True:
        for spawner in spawners:
            spawner.update()
            time.sleep(60 / len(spawners))
