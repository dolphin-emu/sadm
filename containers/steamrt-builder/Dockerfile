FROM registry.gitlab.steamos.cloud/steamrt/sniper/sdk:latest

RUN apt update

# Buildbot worker and build tools dependencies
RUN apt install -y ninja-build buildbot-worker git cmake p7zip-full

RUN apt clean

# Buildbot setup. Use fake values for initial creation to replace with
# environment variables instead.
RUN buildbot-worker create-worker \
  /buildbot \
  BUILDBOT_HOST \
  WORKER_NAME \
  WORKER_PASSWORD && \
  sed -i "s/'BUILDBOT_HOST'/os.environ['BUILDBOT_HOST']/" /buildbot/buildbot.tac && \
  sed -i "s/'WORKER_NAME'/os.environ.pop('WORKER_NAME')/" /buildbot/buildbot.tac && \
  sed -i "s/'WORKER_PASSWORD'/os.environ.pop('WORKER_PASSWORD')/" /buildbot/buildbot.tac
RUN echo 'OatmealDome <oatmeal@dolphin-emu.org>' > /buildbot/info/admin
RUN echo 'SteamRT "sniper" build container' > /buildbot/info/host

ENTRYPOINT cd /buildbot && exec buildbot-worker start --nodaemon
