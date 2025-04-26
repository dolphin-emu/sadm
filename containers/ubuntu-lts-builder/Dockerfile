FROM ubuntu:24.04 as cf-build

RUN apt update

# Build dependencies for LLVM - we need an outdated GCC as newer ones have problems
# when compiling an LLVM version this out of date
RUN apt install -y build-essential gcc-9 g++-9 python3 cmake ninja-build wget

RUN mkdir /work && \
  cd /work && \
  wget https://github.com/llvm/llvm-project/releases/download/llvmorg-13.0.1/llvm-13.0.1.src.tar.xz -O llvm.tar.xz && \
  tar xf llvm.tar.xz && \
  mv llvm-13.0.1.src llvm && \
  wget https://github.com/llvm/llvm-project/releases/download/llvmorg-13.0.1/clang-13.0.1.src.tar.xz -O clang.tar.xz && \
  tar xf clang.tar.xz && \
  mv clang-13.0.1.src clang

RUN mkdir -p /work/llvm/build && \
  cd /work/llvm/build && \
  cmake .. -G Ninja -DCMAKE_BUILD_TYPE="Release" -DLLVM_TARGETS_TO_BUILD=X86 -DCMAKE_C_COMPILER="gcc-9" -DCMAKE_CXX_COMPILER="g++-9" -DLLVM_ENABLE_PROJECTS="clang" && \
  ninja clang-format

FROM ubuntu:24.04

RUN apt update

# Tools used for container setup.
RUN apt install -y wget unzip

# Dolphin build dependencies
RUN apt install -y \
  build-essential git cmake ffmpeg libavcodec-dev libavformat-dev \
  libavutil-dev libswscale-dev libevdev-dev libudev-dev libxrandr-dev \
  libxi-dev libpangocairo-1.0-0 qt6-base-dev qt6-base-private-dev \
  libqt6svg6-dev libbluetooth-dev libasound2-dev libpulse-dev libgl1-mesa-dev

# Android build dependencies
RUN apt install -y openjdk-11-jdk-headless openjdk-17-jdk-headless

# Buildbot worker dependencies
RUN apt install -y ninja-build buildbot-worker clang-format-19

# clang-format-13 from the previous stage
COPY --from=cf-build /work/llvm/build/bin/clang-format /usr/local/bin/clang-format-13

# Android Studio setup (for Java linting)
RUN cd / && \
  wget https://redirector.gvt1.com/edgedl/android/studio/ide-zips/2024.3.1.15/android-studio-2024.3.1.15-linux.tar.gz -O android-studio.tar.gz && \
  tar xf android-studio.tar.gz && \
  rm android-studio.tar.gz

ENV ANDROID_STUDIO_ROOT=/android-studio

# Android CLI setup and NDK.
RUN mkdir -p /Android/cmdline-tools && cd /Android/cmdline-tools && \
  wget https://dl.google.com/android/repository/commandlinetools-linux-13114758_latest.zip -O android-cli.zip && \
  unzip android-cli.zip && \
  mv cmdline-tools latest && \
  rm android-cli.zip
RUN yes | /Android/cmdline-tools/latest/bin/sdkmanager --licenses
RUN /Android/cmdline-tools/latest/bin/sdkmanager --install 'cmake;3.22.1'
RUN /Android/cmdline-tools/latest/bin/sdkmanager --install 'ndk;27.0.12077973'

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
RUN echo 'OatmealDome <oatmeal@dolphin-emu.org>' > /buildbot/info/admin
RUN echo 'Ubuntu 24.04 LTS (Noble Numbat) build container' > /buildbot/info/host

ENTRYPOINT cd /buildbot && exec buildbot-worker start --nodaemon
