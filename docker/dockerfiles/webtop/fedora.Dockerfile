ARG WEBTOP_BASE_IMAGE=lscr.io/linuxserver/webtop:fedora-xfce
FROM ${WEBTOP_BASE_IMAGE}

USER root

COPY docker/config/packages/no-screensavers.dnf.conf /tmp/no-screensavers.conf
RUN sed -i '/^\[main\]/r /tmp/no-screensavers.conf' /etc/dnf/dnf.conf && rm /tmp/no-screensavers.conf

# __INJECT_BEFORE_DEPS__
RUN dnf install -y \
        supervisor && \
    dnf clean all
