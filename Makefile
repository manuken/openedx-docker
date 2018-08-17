.PHONY: all android configure build update migrate assets up daemon

USERID ?= $$(id -u)
EDX_PLATFORM_SETTINGS ?= universal.production
DOCKER_COMPOSE_RUN = docker-compose run --rm
DOCKER_COMPOSE_RUN_OPENEDX = $(DOCKER_COMPOSE_RUN) -e USERID=$(USERID) -e SETTINGS=$(EDX_PLATFORM_SETTINGS)
ifneq ($(EDX_PLATFORM_PATH),)
	DOCKER_COMPOSE_RUN_OPENEDX += --volume="$(EDX_PLATFORM_PATH):/openedx/edx-platform"
endif

DOCKER_COMPOSE_RUN_LMS = $(DOCKER_COMPOSE_RUN_OPENEDX) -p 8000:8000 lms
DOCKER_COMPOSE_RUN_CMS = $(DOCKER_COMPOSE_RUN_OPENEDX) -p 8001:8001 cms

post_configure_targets = 
ifeq ($(ACTIVATE_HTTPS), 1)
	post_configure_targets += https-certificate
endif

all: configure $(post_configure_targets) update migrate assets daemon
	@echo "All set \o/ You can access the LMS at http://localhost and the CMS at http://studio.localhost"

##################### Bootstrapping

configure:
	docker build -t regis/openedx-configurator:latest configurator/
	docker run --rm -it --volume="$(PWD)/config:/openedx/config" \
		-e USERID=$(USERID) -e SILENT=$(SILENT) -e ACTIVATE_HTTPS=$(ACTIVATE_HTTPS) \
		regis/openedx-configurator

update:
	docker-compose pull

provision:
	$(DOCKER_COMPOSE_RUN) lms bash -c "dockerize -wait tcp://mysql:3306 -timeout 20s && bash /openedx/config/provision.sh"

migrate-openedx:
	$(DOCKER_COMPOSE_RUN_OPENEDX) lms bash -c "dockerize -wait tcp://mysql:3306 -timeout 20s && ./manage.py lms migrate"
	$(DOCKER_COMPOSE_RUN_OPENEDX) cms bash -c "dockerize -wait tcp://mysql:3306 -timeout 20s && ./manage.py cms migrate"

migrate-forum:
	$(DOCKER_COMPOSE_RUN) forum bash -c "bundle exec rake search:initialize && \
		bundle exec rake search:rebuild_index"

migrate-xqueue:
	$(DOCKER_COMPOSE_RUN) xqueue bash -c "./manage.py migrate"

migrate: provision migrate-openedx migrate-forum migrate-xqueue

assets:
	$(DOCKER_COMPOSE_RUN_OPENEDX) -e NO_PREREQ_INSTALL=True lms paver update_assets lms --settings=$(EDX_PLATFORM_SETTINGS)
	$(DOCKER_COMPOSE_RUN_OPENEDX) -e NO_PREREQ_INSTALL=True cms paver update_assets cms --settings=$(EDX_PLATFORM_SETTINGS)

##################### Running

up:
	docker-compose up

daemon:
	docker-compose up -d && \
	echo "Daemon is up and running"

stop:
	docker-compose rm --stop --force

##################### Extra

info:
	uname -a
	@echo "-------------------------"
	docker version
	@echo "-------------------------"
	docker-compose --version
	@echo "-------------------------"
	echo $$EDX_PLATFORM_PATH
	echo $$EDX_PLATFORM_SETTINGS

import-demo-course:
	$(DOCKER_COMPOSE_RUN_OPENEDX) cms /bin/bash -c "git clone https://github.com/edx/edx-demo-course ../edx-demo-course && git -C ../edx-demo-course checkout open-release/hawthorn.beta1 && python ./manage.py cms import ../data ../edx-demo-course"

create-staff-user:
	$(DOCKER_COMPOSE_RUN_OPENEDX) lms /bin/bash -c "./manage.py lms manage_user --superuser --staff ${USERNAME} ${EMAIL} && ./manage.py lms changepassword ${USERNAME}"

https-certificate:
	docker run --rm -it \
		--volume="$(PWD)/config/letsencrypt/:/openedx/letsencrypt/config/" \
		--volume="$(PWD)/data/letsencrypt/:/etc/letsencrypt/" \
		--entrypoint "/openedx/letsencrypt/config/certonly.sh" \
		certbot/certbot 

##################### Development

lms:
	$(DOCKER_COMPOSE_RUN_LMS) bash
cms:
	$(DOCKER_COMPOSE_RUN_CMS) bash

lms-shell:
	$(DOCKER_COMPOSE_RUN_OPENEDX) lms ./manage.py lms shell
cms-shell:
	$(DOCKER_COMPOSE_RUN_OPENEDX) cms ./manage.py cms shell


#################### Android app

android:
	docker-compose -f docker-compose-android.yml run --rm android
	@echo "Your APK file is ready: ./data/android/edx-prod-debuggable-2.14.0.apk"

android-release:
	# Note that this requires that you edit ./config/android/gradle.properties
	docker-compose -f docker-compose-android.yml run --rm android ./gradlew assembleProdRelease

android-build:
	docker build -t regis/openedx-android:latest android/
android-push:
	docker push regis/openedx-android:latest
android-dockerhub: android-build android-push


#################### Deploying to docker hub

build:
	# We need to build with docker, as long as docker-compose cannot push to dockerhub
	docker build -t regis/openedx:latest -t regis/openedx:hawthorn openedx/
	docker build -t regis/openedx-forum:latest -t regis/openedx-forum:hawthorn forum/
	docker build -t regis/openedx-xqueue:latest -t regis/openedx-xqueue:hawthorn xqueue/

push:
	docker push regis/openedx:hawthorn
	docker push regis/openedx:latest
	docker push regis/openedx-forum:hawthorn
	docker push regis/openedx-forum:latest
	docker push regis/openedx-xqueue:hawthorn
	docker push regis/openedx-xqueue:latest

dockerhub: build push
