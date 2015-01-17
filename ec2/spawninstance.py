import boto.ec2
import requests
import sys
import time
import yaml


def median(l):
    half = len(l) // 2
    l.sort()
    if len(l) % 2 == 0:
        return (l[half - 1] + l[half]) / 2
    else:
        return l[half]


class Spawner(object):
    def __init__(self, cfg, ec2, buildbot_cfg):
        self.cfg = cfg
        self.ec2 = ec2
        self.buildbot_cfg = buildbot_cfg
        self.last_empty_time = 0

    def log(self, msg, *args):
        print(self.cfg['name'] + ': ' + (msg % args))

    def get_queue_avg_length(self):
        pending = 0
        for builder in self.cfg['builders']:
            try:
                url = self.buildbot_cfg['url'] + '/json/builders/' + builder
                data = requests.get(url).json()
                pending += data.get('pendingBuilds', 0)
            except Exception as e:
                self.log('Error while fetching builder %s: %s', builder, e)
        return pending / len(self.cfg['builders'])

    def has_unfulfilled_spot_request(self):
        filters = {'launch.image-id': self.cfg['ami']}
        results = self.ec2.get_all_spot_instance_requests(filters=filters)
        for r in results:
            if r.state in ['open', 'active']:
                return True
        return False

    def get_spot_price(self):
        history = self.ec2.get_spot_price_history(
                instance_type=self.cfg['type'],
                product_description=self.cfg['product'],
                max_results=50)
        median_price = median([h.price for h in history])
        return median_price * 0.9995

    def create_spot_request(self):
        price = self.get_spot_price()
        self.log('Spot price: $%.5f', price)
        self.ec2.request_spot_instances(price, self.cfg['ami'],
                key_name=self.cfg['keypair'],
                security_group_ids=[self.cfg['security_group']],
                instance_type=self.cfg['type'])

    def update(self):
        self.log('Starting update')
        avg_length = self.get_queue_avg_length()
        self.log('Average length: %.2f', avg_length)
        if avg_length == 0:
            self.last_empty_time = time.time()
            return
        if self.has_unfulfilled_spot_request():
            self.log('Unfulfilled spot requests found, not doing anything')
            # TODO: Potentially increase price.
            return
        if avg_length >= self.cfg['max_queue_avg'] or \
            time.time() - self.last_empty_time >= self.cfg['max_latency']:
            self.log('Creating a new spot request')
            self.create_spot_request()
            self.last_empty_time = time.time()

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
