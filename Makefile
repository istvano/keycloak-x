SHELL := /bin/bash

# ===SETUP
BLUE      := $(shell tput -Txterm setaf 4)
GREEN     := $(shell tput -Txterm setaf 2)
TURQUOISE := $(shell tput -Txterm setaf 6)
WHITE     := $(shell tput -Txterm setaf 7)
YELLOW    := $(shell tput -Txterm setaf 3)
GREY      := $(shell tput -Txterm setaf 1)
RESET     := $(shell tput -Txterm sgr0)

SMUL      := $(shell tput smul)
RMUL      := $(shell tput rmul)

# Variable wrapper
define defw
	custom_vars += $(1)
	$(1) ?= $(2)
	export $(1)
	shell_env += $(1)="$$($(1))"
endef

# Variable wrapper for hidden variables
define defw_h
	$(1) := $(2)
	shell_env += $(1)="$$($(1))"
endef

# Add the following 'help' target to your Makefile
# And add help text after each target name starting with '\#\#'
# A category can be added with @category
HELP_FUN = \
	%help; \
	use Data::Dumper; \
	while(<>) { \
		if (/^([_a-zA-Z0-9\-\/]+)\s*:.*\#\#(?:@([a-zA-Z0-9\-\/_\s]+))?\t(.*)$$/ \
			|| /^([_a-zA-Z0-9\-\/]+)\s*:.*\#\#(?:@([a-zA-Z0-9\-\/]+))?\s(.*)$$/) { \
			$$c = $$2; $$t = $$1; $$d = $$3; \
			push @{$$help{$$c}}, [$$t, $$d, $$ARGV] unless grep { grep { grep /^$$t$$/, $$_->[0] } @{$$help{$$_}} } keys %help; \
		} \
	}; \
	for (sort keys %help) { \
		printf("${WHITE}%24s:${RESET}\n\n", $$_); \
		for (@{$$help{$$_}}) { \
			printf("%s%25s${RESET}%s  %s${RESET}\n", \
				( $$_->[2] eq "Makefile" || $$_->[0] eq "help" ? "${YELLOW}" : "${GREY}"), \
				$$_->[0], \
				( $$_->[2] eq "Makefile" || $$_->[0] eq "help" ? "${GREEN}" : "${GREY}"), \
				$$_->[1] \
			); \
		} \
		print "\n"; \
	}


default: help

.PHONY: help
help:: ##@Other Show this help.
	@echo ""
	@printf "%30s " "${BLUE}VARIABLES"
	@echo "${RESET}"
	@echo ""
	@printf "${BLUE}%25s${RESET}${TURQUOISE}  ${SMUL}%s${RESET}\n" $(foreach v, $(custom_vars), $v $(if $($(v)),$($(v)), ''))
	@echo ""
	@echo ""
	@echo ""
	@printf "%30s " "${YELLOW}TARGETS"
	@echo "${RESET}"
	@echo ""
	@perl -e '$(HELP_FUN)' $(MAKEFILE_LIST)

# === BEGIN USER OPTIONS ===
# import env file
# You can change the default config with `make env="youfile.env" build`
env ?= .env
include $(env)
export $(shell sed 's/=.*//' $(env))

MFILECWD = $(shell pwd)
ETC=$(MFILECWD)/etc
TLS=$(ETC)/tls

#space separated string array ->
$(eval $(call defw,NAMESPACES,keycloak-test))
$(eval $(call defw,DEFAULT_NAMESPACE,$(shell echo $(NAMESPACES) | awk '{print $$1}')))
$(eval $(call defw,ENV,$(ENV)))
$(eval $(call defw,DOMAINS,"www.keycloak.lan"))
$(eval $(call defw,TLS_PORT,8443))
$(eval $(call defw,CLUSTER_NAME,$(shell basename $(MFILECWD))))
$(eval $(call defw,IP_ADDRESS,$(shell hostname -I | awk '{print $$1}')))
$(eval $(call defw,DOCKER,docker))
$(eval $(call defw,COMPOSE,docker-compose))

MAIN_DOMAIN=$(shell echo $(DOMAINS) | awk '{print $$1}')

# === END USER OPTIONS ===

### DNS

.PHONY: dns/create
dns/insert: ##@dns Create dns
	@echo "Creating HOST DNS entries for the project ..."
	@for v in $(DOMAINS) ; do \
		echo $$v; \
		sudo sh -c "sed -zi \"/$$v/!s/$$/\n$(IP_ADDRESS)	$$v/\" /etc/hosts "; \
	done
	@echo "Completed..."

.PHONY: dns/remove
dns/remove: ##@dns Delete dns entries
	@echo "Removing HOST DNS entries ..."
	@for v in $(DOMAINS) ; do \
		echo $$v; \
		sudo sh -c "sed -i \"/$(IP_ADDRESS)	$$v/d\" /etc/hosts"; \
	done
	@echo "Completed..."

### CERTS

.PHONY: tls/create-cert
tls/create-cert:  ##@tls Create self sign certs for local machine
	@echo "Creating self signed certificate"
	(cd $(TLS) && ./self-signed-cert.sh)


.PHONY: tls/trust-cert
tls/trust-cert: ##@tls Trust self signed cert by local browser
	@echo "Import self signed cert into user's truststore"
	@[ -d ~/.pki/nssdb ] || mkdir -p ~/.pki/nssdb
	@certutil -d sql:$$HOME/.pki/nssdb -A -n '$(MAIN_DOMAIN) cert authority' -i $(TLS)/tls-ca/keycloak.lan_ca.crt -t TCP,TCP,TCP
	@certutil -d sql:$$HOME/.pki/nssdb -A -n '$(MAIN_DOMAIN)' -i $(TLS)/tls-ca/keycloak.lan.crt -t P,P,P
	@echo "Import successful..."

### COMPOSE

.PHONY: compose/up
compose/up:  ##@Compose up
	$(COMPOSE) --project-name=$(PROJECT) up

.PHONY: compose/ps
compose/ps:  ##@Compose show processes
	$(COMPOSE) --project-name=$(PROJECT) ps

### DOCKER
.PHONY: build
build:  ##@Docker build docker image
	$(DOCKER) build . -t $(APP)

.PHONY: build-nc
build-nc:  ##@Docker build docker image without using cache
	$(DOCKER) build . -t $(APP)

.PHONY: tag
tag: tag-latest tag-version ##@Docker Generate container tags for the `{version}` ans `latest` tags

.PHONY: tag-latest
tag-latest:
	@echo 'creating tag :latest'
	$(DOCKER) tag $(APP) $(DOCKER_REPO)/$(APP):latest

.PHONY: tag-version
tag-version:
	@echo 'creating tag $(VERSION)'
	$(DOCKER) tag $(APP) $(DOCKER_REPO)/$(APP):$(VERSION)

.PHONY: release
release: build-nc publish ##@Docker Build without cache and tag the docker image

.PHONY: publish
publish: push-tag push-latest

.PHONY: push-latest
push-latest:
	$(DOCKER) push $(DOCKER_REPO)/$(APP):latest

.PHONY: push-tag
push-tag:
	$(DOCKER) push $(DOCKER_REPO)/$(APP):$(VERSION)

### DEVELOPMENT

.PHONY: run
run: ##@dev Start docker container
	$(DOCKER) run -i -t --rm \
		--env-file=./.env \
		--name="$(APP)" \
		--mount type=bind,source=$(MFILECWD)/etc/tls/tls-ca,target=/etc/ssl/certs/keycloak \
		-e KC_DB=dev-mem \
		-p 8080:8080 \
		-p $(TLS_PORT):8443 \
		-p 8787:8787 \
		$(BASE-IMAGE) \
		start-dev

.PHONY: kc/migrate
kc/migrate: ##@dev Run migrations
	$(DOCKER) run --network=host \
	-e KEYCLOAK_URL=https://$(MAIN_DOMAIN):$(TLS_PORT)/ \
	-e KEYCLOAK_USER=$(KEYCLOAK_ADMIN) \
	-e KEYCLOAK_PASSWORD=$(KEYCLOAK_ADMIN_PASSWORD) \
	-e KEYCLOAK_SSLVERIFY=false \
	-e WAIT_TIME_IN_SECONDS=120 \
	-e SPRING_PROFILES_INCLUDE=debug \
	-e IMPORT_PATH=/config \
	-e IMPORT_FORCE=false \
	--mount type=bind,source="$$(pwd)"/etc/conf/keycloak,target=/config \
	adorsys/keycloak-config-cli:$(KEYCLOAK-MIGRATE)


### MISC

.PHONY: init
init: tls/create-cert tls/trust-cert dns/insert## Initialize the environment by creating cert manager
	@echo "Init completed"

.PHONY: synctime
synctime: ##@misc Sync VM time
	@sudo sudo timedatectl set-ntp off
	@sudo timedatectl set-ntp on
	@date

.PHONY: versions
versions: ##@misc Print the "imporant" tools versions out for easier debugging.
	@echo "=== BEGIN Version Info ==="
	@echo "Project name: ${PROJECT}"
	@echo "version: ${VERSION}"
	@echo "Repo state: $$(git rev-parse --verify HEAD) (dirty? $$(if git diff --quiet; then echo 'NO'; else echo 'YES'; fi))"
	@echo "make: $$(command -v make)"
	@echo "kubectl: $$(command -v kubectl)"
	@echo "grep: $$(command -v grep)"
	@echo "cut: $$(command -v cut)"
	@echo "rsync: $$(command -v rsync)"
	@echo "openssl: $$(command -v openssl)"
	@echo "/dev/urandom: $$(if test -c /dev/urandom; then echo OK; else echo 404; fi)"
	@echo "=== END Version Info ==="

.EXPORT_ALL_VARIABLES:
