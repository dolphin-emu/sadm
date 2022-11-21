FROM registry.gitlab.steamos.cloud/steamrt/sniper/sdk:latest

RUN apt update

# Dolphin build dependencies
RUN apt install -y \
  build-essential git cmake ffmpeg libavcodec-dev libavformat-dev \
  libavutil-dev libswscale-dev libevdev-dev libudev-dev libxrandr-dev \
  libxi-dev libpangocairo-1.0-0 qtbase5-dev qtchooser qt5-qmake \
  qtbase5-dev-tools qtbase5-private-dev libbluetooth-dev libasound2-dev \
  libpulse-dev

# Buildbot worker dependencies
RUN apt install -y ninja-build buildbot-worker

RUN apt clean

# Buildbot setup. Use fake values for initial creation to replace with
# environment variables instead.
RUN buildbot-worker create-worker \
  /buildbot \
  BUILDBOT_HOST \
  WORKER_NAME \
  WORKER_PASSWORD && \
  sed -i "s/'BUILDBOT_HOST'/os.environ['BUILDBOT_HOST']/" /buildbot/buildbot.tac && \
  sed -i "s/'WORKER_NAME'/os.environ['WORKER_NAME']/" /buildbot/buildbot.tac && \
  sed -i "s/'WORKER_PASSWORD'/os.environ['WORKER_PASSWORD']/" /buildbot/buildbot.tac
RUN echo 'Pierre Bourdon <delroth@dolphin-emu.org>' > /buildbot/info/admin
RUN echo 'SteamRT "spider" build container' > /buildbot/info/host

ENTRYPOINT cd /buildbot && buildbot-worker start --nodaemon
