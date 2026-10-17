FROM debian:bookworm-backports

ENV APPIMAGE_EXTRACT_AND_RUN=1

RUN apt update

# Basic build tools
RUN apt install -y build-essential git cmake ninja-build wget unzip

# Buildbot worker dependencies
RUN apt install -y ninja-build buildbot-worker

# Dolphin build dependencies
RUN apt install -y \
  qt6-base-dev qt6-base-private-dev qt6-svg-dev \
  libgl1-mesa-dev \
  libx11-dev \
  libxrandr-dev \
  libxi-dev \
  pkg-config \
  libegl1-mesa-dev \
  libavcodec-dev \
  libavformat-dev \
  libavutil-dev \
  libswresample-dev \
  libswscale-dev \
  libudev-dev \
  libevdev-dev \
  libsystemd-dev \
  libasound2-dev \
  libpulse-dev \
  libbluetooth-dev \
  gettext

# appimagetool requirement
RUN apt install -y file

RUN apt clean

RUN mkdir /tools

RUN wget -O /tools/linuxdeploy.AppImage "https://github.com/linuxdeploy/linuxdeploy/releases/download/continuous/linuxdeploy-$(uname -m).AppImage"
RUN wget -O /tools/linuxdeploy-plugin-qt.AppImage "https://github.com/linuxdeploy/linuxdeploy-plugin-qt/releases/download/continuous/linuxdeploy-plugin-qt-$(uname -m).AppImage"
RUN wget -O /tools/appimagetool.AppImage "https://github.com/AppImage/appimagetool/releases/download/continuous/appimagetool-$(uname -m).AppImage"

RUN chmod a+x /tools/linuxdeploy.AppImage
RUN chmod a+x /tools/linuxdeploy-plugin-qt.AppImage
RUN chmod a+x /tools/appimagetool.AppImage

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
RUN echo 'Debian 12 (bookworm) AppImage build container' > /buildbot/info/host

ENTRYPOINT cd /buildbot && exec buildbot-worker start --nodaemon
