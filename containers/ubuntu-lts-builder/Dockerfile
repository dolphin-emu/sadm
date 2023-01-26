FROM ubuntu:22.04

RUN apt update

# Tools used for container setup.
RUN apt install -y wget unzip

# Dolphin build dependencies
RUN apt install -y \
  build-essential git cmake ffmpeg libavcodec-dev libavformat-dev \
  libavutil-dev libswscale-dev libevdev-dev libudev-dev libxrandr-dev \
  libxi-dev libpangocairo-1.0-0 qtbase5-dev qtchooser qt5-qmake \
  qtbase5-dev-tools qtbase5-private-dev libbluetooth-dev libasound2-dev \
  libpulse-dev

# Android build dependencies
RUN apt install -y openjdk-11-jdk-headless

# Buildbot worker dependencies
RUN apt install -y ninja-build buildbot-worker clang-format-12

# Android Studio setup (for Java linting)
RUN cd / && \
  wget https://redirector.gvt1.com/edgedl/android/studio/ide-zips/2021.2.1.15/android-studio-2021.2.1.15-linux.tar.gz -O android-studio.tar.gz && \
  tar xf android-studio.tar.gz && \
  rm android-studio.tar.gz

ENV ANDROID_STUDIO_ROOT=/android-studio

# Android CLI setup and NDK.
RUN mkdir -p /Android/cmdline-tools && cd /Android/cmdline-tools && \
  wget https://dl.google.com/android/repository/commandlinetools-linux-8512546_latest.zip -O android-cli.zip && \
  unzip android-cli.zip && \
  mv cmdline-tools latest && \
  rm android-cli.zip
RUN /Android/cmdline-tools/latest/bin/sdkmanager --install 'cmake;3.18.1'
RUN /Android/cmdline-tools/latest/bin/sdkmanager --install 'ndk;25.1.8937393'
RUN yes | /Android/cmdline-tools/latest/bin/sdkmanager --licenses

ENV ANDROID_HOME=/Android

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
RUN echo 'Jammy (22.04 LTS) build container' > /buildbot/info/host

ENTRYPOINT cd /buildbot && exec buildbot-worker start --nodaemon