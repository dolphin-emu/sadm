FROM debian:bullseye-backports

RUN apt update

# Tools used for container setup.
RUN apt install -y wget unzip

# Dolphin build dependencies
RUN apt install -y \
  build-essential git cmake ffmpeg libavcodec-dev libavformat-dev \
  libavutil-dev libswscale-dev libevdev-dev libudev-dev libxrandr-dev \
  libxi-dev libpangocairo-1.0-0 qt6-base-dev qt6-base-private-dev \
  qt6-svg-dev libbluetooth-dev libasound2-dev libpulse-dev

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
  sed -i "s/'WORKER_NAME'/os.environ.pop('WORKER_NAME')/" /buildbot/buildbot.tac && \
  sed -i "s/'WORKER_PASSWORD'/os.environ.pop('WORKER_PASSWORD')/" /buildbot/buildbot.tac
RUN echo 'Pierre Bourdon <delroth@dolphin-emu.org>' > /buildbot/info/admin
RUN echo 'Debian 11 (Bullseye) build container' > /buildbot/info/host

ENTRYPOINT cd /buildbot && exec buildbot-worker start --nodaemon
