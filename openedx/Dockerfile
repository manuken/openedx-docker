FROM ubuntu:16.04

############ common to lms & cms

# Install system requirements
RUN apt update && \
  apt upgrade -y && \
  # Global requirements
  apt install -y language-pack-en git python-virtualenv build-essential software-properties-common curl git-core libxml2-dev libxslt1-dev python-pip libmysqlclient-dev python-apt python-dev libxmlsec1-dev libfreetype6-dev swig gcc g++ && \
  # openedx requirements
  apt install -y gettext gfortran graphviz graphviz-dev libffi-dev libfreetype6-dev libgeos-dev libjpeg8-dev liblapack-dev libpng12-dev libsqlite3-dev libxml2-dev libxmlsec1-dev libxslt1-dev nodejs npm ntp pkg-config && \
  # Our requirements
  apt install -y mysql-client

# Install symlink so that we have access to 'node' binary without virtualenv.
# This replaces the "nodeenv" install.
RUN apt install -y nodejs-legacy

# Static assets will reside in /openedx/data and edx-platform will be
# checked-out in /openedx/
RUN mkdir /openedx /openedx/data /openedx/edx-platform
WORKDIR /openedx/edx-platform

## Checkout edx-platform code
ARG EDX_PLATFORM_REPOSITORY=https://github.com/edx/edx-platform.git
ARG EDX_PLATFORM_VERSION=open-release/hawthorn.1
RUN git clone $EDX_PLATFORM_REPOSITORY --branch $EDX_PLATFORM_VERSION --depth 1 .

# Install python requirements (clone source repos in a separate dir, otherwise
# will be overwritten when we mount edx-platform)
RUN pip install --src ../venv/src -r requirements/edx/base.txt

# Install nodejs requirements
RUN npm install
ENV PATH ./node_modules/.bin:${PATH}

# Link configuration files to common /openedx/config folder, which should later
# be mounted as a volume. Note that this image will not be functional until
# config files have been mounted inside the container
RUN mkdir /openedx/config
RUN ln -s /openedx/config/universal/lms/ /openedx/edx-platform/lms/envs/universal \
  && ln -s /openedx/config/universal/cms/ /openedx/edx-platform/cms/envs/universal
RUN ln -s /openedx/config/lms.env.json /openedx/ \
  && ln -s /openedx/config/cms.env.json /openedx/ \
  && ln -s /openedx/config/lms.auth.json /openedx/ \
  && ln -s /openedx/config/cms.auth.json /openedx/

# Dockerize will be useful to wait for mysql DB availability
ENV DOCKERIZE_VERSION v0.6.1
RUN curl -L -o dockerize.tar.gz https://github.com/jwilder/dockerize/releases/download/$DOCKERIZE_VERSION/dockerize-linux-amd64-$DOCKERIZE_VERSION.tar.gz \
    && tar -C /usr/local/bin -xzvf dockerize.tar.gz \
    && rm dockerize.tar.gz

# Copy convenient scripts
COPY ./bin/docker-entrypoint.sh /usr/local/bin/

# service variant is "lms" or "cms"
ENV SERVICE_VARIANT lms
ENV SETTINGS universal.production

# Entrypoint will fix permissiosn of all files and run commands as openedx
ENTRYPOINT ["docker-entrypoint.sh"]

# Run server
EXPOSE 8000
CMD gunicorn --name ${SERVICE_VARIANT} --bind=0.0.0.0:8000 --max-requests=1000 ${SERVICE_VARIANT}.wsgi:application
