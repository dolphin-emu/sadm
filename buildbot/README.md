To start a local development server at [http://localhost:8010](http://localhost:8010), run:

```bash
pip install 'buildbot[bundle]' buildbot-worker
DOLPHIN_BUILDBOT_LOCAL=1 buildbot stop
DOLPHIN_BUILDBOT_LOCAL=1 buildbot create-master -r
DOLPHIN_BUILDBOT_LOCAL=1 buildbot upgrade-master
( trap 'echo "Stopping buildbot..."; DOLPHIN_BUILDBOT_LOCAL=1 buildbot stop' INT && DOLPHIN_BUILDBOT_LOCAL=1 buildbot start && tail -f twistd.log )
```

If no workers are attached, you may need to [manually set up an in-process LocalWorker](http://docs.buildbot.net/latest/manual/cfg-workers.html#local-workers).

To manually build a pull request, go to the `central` module in the parent directory and run:

```python
import buildbot
import config
import uuid

PULL_REQUEST = 5320

with open('config.yml') as f:
    config.load(f)

buildbot.cfg.buildbot.jobdir = '../buildbot/pr-jobdir'

buildbot.send_build_request(buildbot.make_build_request(
    repo="https://github.com/dolphin-emu/dolphin.git",
    pr_id=PULL_REQUEST,
    job_id="pr-%s" % PULL_REQUEST,
    baserev="",
    headrev="",
    who="me",
    comment=""))
```
