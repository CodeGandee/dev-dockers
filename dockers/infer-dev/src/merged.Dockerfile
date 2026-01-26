# syntax=docker/dockerfile:1

# the base image
ARG BASE_IMAGE_1=ubuntu:22.04
FROM ${BASE_IMAGE_1} AS stage1

# installation parts on/off
ARG WITH_ESSENTIAL_APPS=false
ARG WITH_CUSTOM_APPS=false
ARG WITH_SSH=false
ARG ROOT_PASSWORD

# if you want to use proxy for apt, set this to host proxy
# like http://host.docker.internal:7890
ARG APT_USE_PROXY

# keep the http proxy for apt after installation?
ARG APT_KEEP_PROXY

# number of retries for apt
ARG APT_NUM_RETRY=3

# use other apt source?
ARG APT_SOURCE_FILE

# keep the apt source file after installation?
ARG KEEP_APT_SOURCE_FILE=false

# ssh user and password
# can be a list of users and passwords, separated by comma
ARG SSH_USER_NAME
ARG SSH_USER_PASSWORD
ARG SSH_USER_UID
ARG SSH_USER_GID
ARG SSH_CONTAINER_PORT

# path to the public key file for the ssh user
# if specified, will be added to the authorized_keys
# if multiple users, separate the keys by comma
ARG SSH_PUBKEY_FILE

# path to the private key file for the ssh user
# if specified, will be installed in user's .ssh directory
# if multiple users, separate the keys by comma
ARG SSH_PRIVKEY_FILE

# user provided proxy
ARG PEI_HTTP_PROXY_1
ARG PEI_HTTPS_PROXY_1
ARG ENABLE_GLOBAL_PROXY=false
ARG REMOVE_GLOBAL_PROXY_AFTER_BUILD=false

# path to installation directory
ARG PEI_STAGE_HOST_DIR_1
ARG PEI_STAGE_DIR_1

# bake environment variables into the image?
ARG PEI_BAKE_ENV_STAGE_1=false

# -------------------------------------------
ENV PEI_HTTP_PROXY_1=${PEI_HTTP_PROXY_1}
ENV PEI_HTTPS_PROXY_1=${PEI_HTTPS_PROXY_1}
ENV PEI_STAGE_DIR_1=${PEI_STAGE_DIR_1}

# create a dir called pei-docker in root, to store logs
RUN mkdir -p /pei-init
ENV PEI_DOCKER_DIR="/pei-init"

# copy installation/internals and installation/system to the image, do apt installs first
ADD ${PEI_STAGE_HOST_DIR_1}/internals ${PEI_STAGE_DIR_1}/internals
ADD ${PEI_STAGE_HOST_DIR_1}/generated ${PEI_STAGE_DIR_1}/generated
ADD ${PEI_STAGE_HOST_DIR_1}/system ${PEI_STAGE_DIR_1}/system

# convert $PEI_STAGE_DIR_1/internals/setup-env.sh from CRLF to LF
# do not use dos2unix, as it is not available in the base image
# and then run the script
RUN sed -i 's/\r$//' $PEI_STAGE_DIR_1/internals/setup-env.sh && \
    chmod +x $PEI_STAGE_DIR_1/internals/setup-env.sh && \
    $PEI_STAGE_DIR_1/internals/setup-env.sh

# prepare apt
RUN apt update
RUN apt-get install --reinstall -y ca-certificates dos2unix

# for any .sh/.bash in PEI_STAGE_DIR_1, including subdirs
# convert CRLF to LF using dos2unix, replace the original
RUN find $PEI_STAGE_DIR_1 -type f \( -name "*.sh" -o -name "*.bash" \) -exec dos2unix {} \;

# add chmod+x to all scripts, including all subdirs
RUN find $PEI_STAGE_DIR_1 -type f \( -name "*.sh" -o -name "*.bash" \) -exec chmod +x {} \;

# show env
RUN env

# install things
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    $PEI_STAGE_DIR_1/internals/install-essentials.sh &&\
    $PEI_STAGE_DIR_1/internals/setup-ssh.sh

RUN $PEI_STAGE_DIR_1/internals/setup-profile-d.sh

# copy the everything to the image
# ADD ${PEI_STAGE_HOST_DIR_1}/custom ${PEI_STAGE_DIR_1}/custom
# ADD ${PEI_STAGE_HOST_DIR_1}/generated ${PEI_STAGE_DIR_1}/generated
# ADD ${PEI_STAGE_HOST_DIR_1}/tmp ${PEI_STAGE_DIR_1}/tmp
ADD ${PEI_STAGE_HOST_DIR_1} ${PEI_STAGE_DIR_1}

# convert CRLF to LF 
RUN find $PEI_STAGE_DIR_1 -type f \( -name "*.sh" -o -name "*.bash" \) -exec dos2unix {} \;

# add chmod+x to all scripts, including all subdirs
RUN find $PEI_STAGE_DIR_1 -type f \( -name "*.sh" -o -name "*.bash" \) -exec chmod +x {} \;

# install custom apps and clean up
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    $PEI_STAGE_DIR_1/internals/custom-on-build.sh

RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    $PEI_STAGE_DIR_1/internals/setup-users.sh &&\
    $PEI_STAGE_DIR_1/internals/cleanup.sh

# allow access to /mnt for all users, so that you can make your own mounts
RUN chmod 777 /mnt

# setup entrypoint
RUN cp $PEI_STAGE_DIR_1/internals/entrypoint.sh /entrypoint.sh &&\
    chmod +x /entrypoint.sh
ENTRYPOINT [ "/entrypoint.sh" ]

# syntax=docker/dockerfile:1

# the base image
# -------------------------------------------
# create workspace for user
FROM stage1 AS final

# paths
ARG PEI_STAGE_HOST_DIR_2
ARG PEI_STAGE_DIR_2
ARG WITH_ESSENTIAL_APPS=false
ARG WITH_CUSTOM_APPS=false

# prefixes and paths
ARG PEI_PREFIX_DATA=data
ARG PEI_PREFIX_APPS=app
ARG PEI_PREFIX_WORKSPACE=workspace
ARG PEI_PREFIX_VOLUME=volume
ARG PEI_PREFIX_IMAGE=image
ARG PEI_PATH_HARD=/hard
ARG PEI_PATH_SOFT=/soft

# derive from stage-1
ARG PEI_HTTP_PROXY_2
ARG PEI_HTTPS_PROXY_2
ARG ENABLE_GLOBAL_PROXY
ARG REMOVE_GLOBAL_PROXY_AFTER_BUILD

# bake environment variables into the image?
ARG PEI_BAKE_ENV_STAGE_1=false

# override stage-1 proxy settings
ENV PEI_HTTP_PROXY_2=${PEI_HTTP_PROXY_2}
ENV PEI_HTTPS_PROXY_2=${PEI_HTTPS_PROXY_2}

# envs
ENV PEI_PREFIX_DATA=${PEI_PREFIX_DATA}
ENV PEI_PREFIX_APPS=${PEI_PREFIX_APPS}
ENV PEI_PREFIX_WORKSPACE=${PEI_PREFIX_WORKSPACE}
ENV PEI_PREFIX_VOLUME=${PEI_PREFIX_VOLUME}
ENV PEI_PREFIX_IMAGE=${PEI_PREFIX_IMAGE}
ENV PEI_PATH_HARD=${PEI_PATH_HARD}
ENV PEI_PATH_SOFT=${PEI_PATH_SOFT}

# for user to directly access soft paths
ENV PEI_SOFT_APPS=${PEI_PATH_SOFT}/${PEI_PREFIX_APPS}
ENV PEI_SOFT_WORKSPACE=${PEI_PATH_SOFT}/${PEI_PREFIX_WORKSPACE}
ENV PEI_SOFT_DATA=${PEI_PATH_SOFT}/${PEI_PREFIX_DATA}

ENV PEI_STAGE_DIR_2=${PEI_STAGE_DIR_2}

# -------------------------------------------
# install essentials

# copy installation/internals and installation/system to the image, do apt installs first
ADD ${PEI_STAGE_HOST_DIR_2}/internals ${PEI_STAGE_DIR_2}/internals
ADD ${PEI_STAGE_HOST_DIR_2}/generated ${PEI_STAGE_DIR_2}/generated
ADD ${PEI_STAGE_HOST_DIR_2}/system ${PEI_STAGE_DIR_2}/system

# install dos2unix, needed for converting CRLF to LF
RUN apt install -y dos2unix

# convert CRLF to LF for scripts in internals and system
# RUN find $PEI_STAGE_DIR_2 -type f -not -path "$PEI_STAGE_DIR_2/tmp/*" -exec sed -i 's/\r$//' {} \;
RUN find $PEI_STAGE_DIR_2 -type f \( -name "*.sh" -o -name "*.bash" \) -exec dos2unix {} \;

# add chmod+x to all scripts, including all subdirs
RUN find $PEI_STAGE_DIR_2 -type f \( -name "*.sh" -o -name "*.bash" \) -exec chmod +x {} \;

# setup and show env
RUN $PEI_STAGE_DIR_2/internals/setup-env.sh && env

# create soft and hard directories
RUN $PEI_STAGE_DIR_2/internals/create-dirs.sh

# install things
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    $PEI_STAGE_DIR_2/internals/install-essentials.sh

# setup profile d
RUN $PEI_STAGE_DIR_2/internals/setup-profile-d.sh

# -------------------------------------------
# run custom scripts

# copy the installation scripts to the image
# ADD ${PEI_STAGE_HOST_DIR_2}/custom ${PEI_STAGE_DIR_2}/custom
# ADD ${PEI_STAGE_HOST_DIR_2}/generated ${PEI_STAGE_DIR_2}/generated
# ADD ${PEI_STAGE_HOST_DIR_2}/tmp ${PEI_STAGE_DIR_2}/tmp
ADD ${PEI_STAGE_HOST_DIR_2} ${PEI_STAGE_DIR_2}

# convert CRLF to LF
# RUN find $PEI_STAGE_DIR_2 -type f -not -path "$PEI_STAGE_DIR_2/tmp/*" -exec sed -i 's/\r$//' {} \;
RUN find $PEI_STAGE_DIR_2 -type f \( -name "*.sh" -o -name "*.bash" \) -exec dos2unix {} \;

# add chmod+x to all scripts, including all subdirs
RUN find $PEI_STAGE_DIR_2 -type f \( -name "*.sh" -o -name "*.bash" \) -exec chmod +x {} \;

# install custom apps
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    $PEI_STAGE_DIR_2/internals/custom-on-build.sh

RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    $PEI_STAGE_DIR_2/internals/setup-users.sh &&\
    $PEI_STAGE_DIR_2/internals/cleanup.sh

# override the entrypoint
RUN cp $PEI_STAGE_DIR_2/internals/entrypoint.sh /entrypoint.sh &&\
    chmod +x /entrypoint.sh
ENTRYPOINT [ "/entrypoint.sh" ]

# install apps to the image
# FROM default AS store-in-image
# ENV X_STORAGE_CHOICE="image-first"
# RUN /installation/scripts/create-links.sh