ARG QEMU_VERSION=4.2.0

# Build stage for qemu-system-arm
FROM debian:stable-slim AS qemu-system-arm-builder
ARG QEMU_VERSION
ENV QEMU_TARBALL="qemu-${QEMU_VERSION}.tar.xz"
WORKDIR /qemu

RUN # Update package lists
RUN apt-get update

RUN # Pull source and verify signatures
RUN apt-get -y install wget
RUN wget "https://download.qemu.org/${QEMU_TARBALL}"

RUN # Verify signatures
RUN apt-get -y install gpg
RUN wget "https://download.qemu.org/${QEMU_TARBALL}.sig"
RUN gpg --keyserver keyserver.ubuntu.com --recv-keys CEACC9E15534EBABB82D3FA03353C9CEF108B584
RUN gpg --verify "${QEMU_TARBALL}.sig" "${QEMU_TARBALL}"

RUN # Extract source tarball
RUN apt-get -y install pkg-config
RUN tar xvf "${QEMU_TARBALL}"

RUN # Build source
# These seem to be the only deps actually required for a successful  build
RUN apt-get -y install python build-essential libglib2.0-dev libpixman-1-dev
# These don't seem to be required but are specified here: https://wiki.qemu.org/Hosts/Linux
RUN apt-get -y install libfdt-dev zlib1g-dev
# Not required or specified anywhere but supress build warnings
RUN apt-get -y install pkg-config flex bison
RUN "qemu-${QEMU_VERSION}/configure" --static --target-list=arm-softmmu
RUN make -j$(nproc)

RUN # Strip the binary, this gives a substantial size reduction!
RUN strip "arm-softmmu/qemu-system-arm"


# Build the dockerpi VM image
FROM busybox:1.31 AS dockerpi-vm
LABEL maintainer="Luke Childs <lukechilds123@gmail.com>"
ARG QEMU_VERSION

COPY --from=qemu-system-arm-builder /qemu/arm-softmmu/qemu-system-arm /usr/local/bin/qemu-system-arm

ADD https://github.com/dhruvvyas90/qemu-rpi-kernel/archive/afe411f2c9b04730bcc6b2168cdc9adca224227c.zip /tmp/qemu-rpi-kernel.zip

RUN cd /tmp && \
    mkdir -p /root/qemu-rpi-kernel && \
    unzip qemu-rpi-kernel.zip && \
    cp -r qemu-rpi-kernel-*/* /root/qemu-rpi-kernel/ && \
    rm -rf /tmp/* /root/qemu-rpi-kernel/README.md /root/qemu-rpi-kernel/tools

VOLUME /sdcard

ADD ./entrypoint.sh /entrypoint.sh
ENTRYPOINT ["./entrypoint.sh"]


# Build the dockerpi image
# It's just the VM image with a compressed Raspbian filesystem added
FROM dockerpi-vm as dockerpi
LABEL maintainer="Luke Childs <lukechilds123@gmail.com>"
ADD http://downloads.raspberrypi.org/raspbian_lite/images/raspbian_lite-2019-09-30/2019-09-26-raspbian-buster-lite.zip /filesystem.zip
