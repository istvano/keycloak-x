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

ifeq ($(OS),Windows_NT)
    CCFLAGS += -D WIN32
    ifeq ($(PROCESSOR_ARCHITEW6432),AMD64)
        CCFLAGS += -D AMD64
    else
        ifeq ($(PROCESSOR_ARCHITECTURE),AMD64)
            CCFLAGS += -D AMD64
        endif
        ifeq ($(PROCESSOR_ARCHITECTURE),x86)
            CCFLAGS += -D IA32
        endif
    endif
else
    UNAME_S := $(shell uname -s)
    ifeq ($(UNAME_S),Linux)
        CCFLAGS += -D LINUX
    endif
    ifeq ($(UNAME_S),Darwin)
        CCFLAGS += -D OSX
    endif
    UNAME_P := $(shell uname -p)
    ifeq ($(UNAME_P),x86_64)
        CCFLAGS += -D AMD64
    endif
    ifneq ($(filter %86,$(UNAME_P)),)
        CCFLAGS += -D IA32
    endif
    ifneq ($(filter arm%,$(UNAME_P)),)
        CCFLAGS += -D ARM
    endif
endif

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

USERNAME=$(shell whoami)
UID=$(shell id -u ${USERNAME})
GID=$(shell id -g ${USERNAME})

MFILECWD = $(shell pwd)
ETC=$(MFILECWD)/etc
TLS=$(ETC)/tls

CRT_FILENAME=tls.pem
KEY_FILENAME=tls.key
DOCKER_BUILD_ARGS=--build-arg KC_FEATURES="$(KC_FEATURES)" --build-arg KC_DB=$(KC_DB)

KC_ADM_CON=--no-config --server http://localhost:8080 --user admin --password admin --realm master
KC_ADM=/opt/keycloak/bin/kcadm.sh
KC_REALM=quickstart
KC_PUBLIC_CLIENT=test-public-client
KC_INTERNAL_CLIENT=test-bearer-internal-client-1

#space separated string array ->
$(eval $(call defw,NAMESPACES,keycloak-test))
$(eval $(call defw,DEFAULT_NAMESPACE,$(shell echo $(NAMESPACES) | awk '{print $$1}')))
$(eval $(call defw,ENV,$(ENV)))
$(eval $(call defw,DOMAINS,keycloak.lan *.keycloak.lan example.test *.example.test))
$(eval $(call defw,TLS_PORT,8443))
$(eval $(call defw,CLUSTER_NAME,$(shell basename $(MFILECWD))))
$(eval $(call defw,IP_ADDRESS,$(IP_ADDRESS)))
$(eval $(call defw,DOCKER,docker))
$(eval $(call defw,COMPOSE,docker-compose))
$(eval $(call defw,UNAME,$(UNAME_S)-$(UNAME_P)))

MAIN_DOMAIN=$(shell echo $(DOMAINS) | awk '{print $$1}')
ifeq ($(UNAME_S),Darwin)
	IP_ADDRESS=$(shell ipconfig getifaddr en0 | awk '{print $$1}')
else
	IP_ADDRESS=$(shell hostname -I | awk '{print $$1}')
endif
ifeq ($(IP_ADDRESS),)
	IP_ADDRESS=127.0.0.1
endif
# === END USER OPTIONS ===

### DNS

.PHONY: dns/create
dns/insert: dns/remove ##@dns Create dns
	@echo "Creating HOST DNS entries for the project ..."
	@for v in $(DOMAINS) ; do \
		echo $$v; \
		sudo -- sh -c -e "echo '$(IP_ADDRESS)	$$v' >> /etc/hosts"; \
	done
	@echo "Completed..."

.PHONY: dns/remove
dns/remove: ##@dns Delete dns entries
	@echo "Removing HOST DNS entries ..."
	@for v in $(DOMAINS) ; do \
		echo $$v; \
		sudo -- sh -c "sed -i.bak \"/$(IP_ADDRESS)	$$v/d\" /etc/hosts && rm /etc/hosts.bak"; \
	done
	@echo "Completed..."

### CERTS

.PHONY: tls/create-cert
tls/create-cert:  ##@tls Create self sign certs for local machine
	@echo "Creating self signed certificate"
	docker run -it --user $(UID):$(UID) \
		--mount "type=bind,src=$(TLS),dst=/home/mkcert" \
		--mount "type=bind,src=$(TLS),dst=/root/.local/share/mkcert" \
		istvano/mkcert:latest -install
	docker run -it --user $(UID):$(UID) \
		--mount "type=bind,src=$(TLS),dst=/home/mkcert" \
		--mount "type=bind,src=$(TLS),dst=/root/.local/share/mkcert" \
		istvano/mkcert:latest -cert-file $(CRT_FILENAME) -key-file $(KEY_FILENAME) $(DOMAINS) localhost 127.0.0.1 ::1


.PHONY: delete-from-store
tls/delete-from-store:
	@[ -d ~/.pki/nssdb ] || mkdir -p ~/.pki/nssdb
	@(if [ -z $(shell certutil -d sql:$$HOME/.pki/nssdb -L | grep '$(MAIN_DOMAIN) cert authority' | head -n1 | awk '{print $$1;}') ]; \
	then \
		echo "not exists. skipping delete"; \
	else \
		certutil -d sql:$$HOME/.pki/nssdb -D -n '$(MAIN_DOMAIN) cert authority'; \
		echo "deleted"; \
	fi)
	@(if [ -z $(shell certutil -d sql:$$HOME/.pki/nssdb -L | grep '$(MAIN_DOMAIN)' | head -n1 | awk '{print $$1;}') ]; \
	then \
		echo "not exists. skipping delete"; \
	else \
		certutil -d sql:$$HOME/.pki/nssdb -D -n '$(MAIN_DOMAIN)'; \
		echo "deleted"; \
	fi)

.PHONY: tls/trust-cert
tls/trust-cert: tls/delete-from-store ##@tls Trust self signed cert by local browser
	@echo "Import self signed cert into user's truststore"
ifeq ($(UNAME_S),Darwin)
	sudo security add-trusted-cert -d -r trustRoot -k /Library/Keychains/System.keychain $(TLS)/.local/share/mkcert/rootCA.pem
else
	@[ -d ~/.pki/nssdb ] || mkdir -p ~/.pki/nssdb
	@certutil -d sql:$$HOME/.pki/nssdb -A -n '$(MAIN_DOMAIN) cert authority' -i $(TLS)/.local/share/mkcert/rootCA.pem -t TCP,TCP,TCP
	@certutil -d sql:$$HOME/.pki/nssdb -A -n '$(MAIN_DOMAIN)' -i $(TLS)/tls.pem -t P,P,P
endif
	@echo "Import successful..."


### COMPOSE

.PHONY: compose/up
compose/up:  ##@Compose up
	$(COMPOSE) --project-name=$(PROJECT) up

.PHONY: compose/ps
compose/ps:  ##@Compose show processes
	$(COMPOSE) --project-name=$(PROJECT) ps

### DOCKER
.PHONY: network/create
network/create: ##@Docker create network
	$(DOCKER) network inspect $(ENV)_sso || $(DOCKER) network create $(ENV)_sso

.PHONY: network/delete
network/delete: ##@Docker create network
	$(DOCKER) network inspect $(ENV)_sso && $(DOCKER) network rm $(ENV)_sso

.PHONY: build
build:  ##@Docker build docker image
	$(DOCKER) build . -t $(APP) $(DOCKER_BUILD_ARGS)

.PHONY: build-nc
build-nc:  ##@Docker build docker image without using cache
	$(DOCKER) build . -t $(APP) $(DOCKER_BUILD_ARGS)

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

### THEMING
.PHONY: theme/build
theme/build: ##@dev Start docker container
	$(DOCKER) run -it --rm \
		--env-file=./.env \
		--mount type=bind,source=$(MFILECWD)/themes,target=/usr/local/src \
		--mount type=bind,source=$(MFILECWD)/etc/tmp/m2,target=/root/.m2 \
		--workdir="/usr/local/src" \
		$(MAVEN_IMAGE) \
		mvn package

### DEVELOPMENT

.PHONY: run
run: ##@dev Start docker container
	$(DOCKER) run -i -t --rm \
		--env-file=./.env \
		-e KC_DB=dev-file \
		-e KC_CACHE=local \
		-e KC_LOG_CONSOLE_COLOR=true \
		-e KC_HTTPS_CERTIFICATE_FILE=/etc/ssl/certs/keycloak/tls.pem \
		-e KC_HTTPS_CERTIFICATE_KEY_FILE=/etc/ssl/certs/keycloak/tls.key \
		-e KC_SPI_LOGIN_PROTOCOL_OPENID_CONNECT_LEGACY_LOGOUT_REDIRECT_URI=true \
		-e KC_SPI_LOGIN_PROTOCOL_OPENID_CONNECT_SUPPRESS_LOGOUT_CONFIRMATION_SCREEN=true \
		--network $(ENV)_sso \
		--name="$(APP)" \
		--mount type=bind,source=$(MFILECWD)/etc/tls,target=/etc/ssl/certs/keycloak \
		--mount type=bind,source=$(MFILECWD)/etc/data,target=/opt/keycloak/data \
		--mount type=bind,source=$(MFILECWD)/themes/src/main/resources/themes,target=/opt/keycloak/themes \
		-p 8080:8080 \
		-p $(TLS_PORT):8443 \
		-p 8787:8787 \
		$(APP):latest \
		start-dev --features=token-exchange,admin-fine-grained-authz,declarative-user-profile

.PHONY: realm/migrate
realm/migrate: ##@realm Run migrations
	$(DOCKER) run \
	--network $(ENV)_sso \
	-e KEYCLOAK_URL=https://keycloak:8443/ \
	-e KEYCLOAK_USER=$(KEYCLOAK_ADMIN) \
	-e KEYCLOAK_PASSWORD=$(KEYCLOAK_ADMIN_PASSWORD) \
	-e KEYCLOAK_SSLVERIFY=false \
	-e WAIT_TIME_IN_SECONDS=120 \
	-e SPRING_PROFILES_INCLUDE=debug \
	-e IMPORT_VARSUBSTITUTION_ENABLED=true \
	-e IMPORT_PATH=/config \
	-e IMPORT_FORCE=false \
	-e REALM_NAME=quickstart \
	-e TEST_CLIENT_SECRET=secret \
	-e TEST_USER_CRED=password \
	-e LOCAL_ADMIN_CRED=password \
	--mount type=bind,source="$$(pwd)"/etc/conf/keycloak,target=/config \
	$(KEYCLOAK_MIGRATE)

### Token exchange

.PHONY: te/enable-permissions
te/enable-permissions: ##@token Enable token exchange for a client
	@(CLIENT_ID=`$(DOCKER) exec -it $(APP) $(KC_ADM) get clients -r $(KC_REALM) --fields id,clientId $(KC_ADM_CON) | sed 1d | jq '.[] | select(.clientId==("'$(KC_INTERNAL_CLIENT)'")) | .id' | sed 's/\"//g'` \
		&& $(DOCKER) exec -it $(APP) $(KC_ADM) update clients/$$CLIENT_ID/management/permissions -r "$(KC_REALM)" -s enabled=true $(KC_ADM_CON) \
		)

.PHONY: te/add-policy
te/add-policy: ##@token Add token exchange client policy
	@(CLIENT_ID=`$(DOCKER) exec -it $(APP) $(KC_ADM) get clients -r $(KC_REALM) --fields id,clientId $(KC_ADM_CON) | sed 1d | jq '.[] | select(.clientId==("'$(KC_PUBLIC_CLIENT)'")) | .id' | sed 's/\"//g'` \
		&& MAN_CLIENT_ID=`$(DOCKER) exec -it $(APP) $(KC_ADM) get clients -r $(KC_REALM) --fields id,clientId $(KC_ADM_CON) | sed 1d | jq '.[] | select(.clientId==("'realm-management'")) | .id' | sed 's/\"//g'` \
		&& echo { \
				\"id\": \"a18a9428-261b-465d-a771-9a23a108cc92\", \
				\"name\": \"token_exchange_policy\", \
				\"type\": \"client\", \
				\"logic\": \"POSITIVE\", \
				\"decisionStrategy\": \"UNANIMOUS\", \
				\"config\": { \"clients\": \"[\\\"$$CLIENT_ID\\\"]\"} \
			} \
			| $(DOCKER) exec -i $(APP) $(KC_ADM) create clients/$$MAN_CLIENT_ID/authz/resource-server/policy -r "$(KC_REALM)" $(KC_ADM_CON) -f - \
		)

.PHONY: te/add-permission
te/add-permission: ##@token Add token exchange client policy
	@(INT_CLIENT_ID=`$(DOCKER) exec -it $(APP) $(KC_ADM) get clients -r $(KC_REALM) --fields id,clientId $(KC_ADM_CON) | sed 1d | jq '.[] | select(.clientId==("'$(KC_INTERNAL_CLIENT)'")) | .id' | sed 's/\"//g'` \
		MAN_CLIENT_ID=`$(DOCKER) exec -it $(APP) $(KC_ADM) get clients -r $(KC_REALM) --fields id,clientId $(KC_ADM_CON) | sed 1d | jq '.[] | select(.clientId==("'realm-management'")) | .id' | sed 's/\"//g'` \
		&& TOKEN_EXCHANGE_SCOPE_ID=`$(DOCKER) exec -it $(APP) $(KC_ADM) get clients/$$MAN_CLIENT_ID/authz/resource-server/scope -r "$(KC_REALM)" $(KC_ADM_CON) | sed 1d |  jq -r '.[] | select(.name==("token-exchange")) | .id'` \
		&& EXCHANGE_POLICY_ID=`$(DOCKER) exec -it $(APP) $(KC_ADM) get clients/$$MAN_CLIENT_ID/authz/resource-server/policy -r "$(KC_REALM)" $(KC_ADM_CON) | sed 1d | jq -r '.[] | select(.name=="token_exchange_policy") | .id'` \
		&& TOKEN_EXCHANGE_PERMISSION_POLICY_ID=`$(DOCKER) exec -it $(APP) $(KC_ADM) get clients/$$MAN_CLIENT_ID/authz/resource-server/policy -r "$(KC_REALM)" $(KC_ADM_CON) | sed 1d | jq -r '.[] | select(.name | startswith("token-exchange.permission.client.'$$INT_CLIENT_ID'")) | .id'` \
		&& CLIENT_RESOURCE_ID=`$(DOCKER) exec -it $(APP) $(KC_ADM) get clients/$$MAN_CLIENT_ID/authz/resource-server/resource -r "$(KC_REALM)" $(KC_ADM_CON) | sed 1d | jq -r '.[] | select(.name | startswith("client.resource.'$$INT_CLIENT_ID'")) | ._id'` \
		&& $(DOCKER) exec -i $(APP) $(KC_ADM) update clients/$$MAN_CLIENT_ID/authz/resource-server/permission/scope/$$TOKEN_EXCHANGE_PERMISSION_POLICY_ID -r "$(KC_REALM)" $(KC_ADM_CON) \
			-s 'scopes=["'$$TOKEN_EXCHANGE_SCOPE_ID'"]' \
			-s 'resources=["'$$CLIENT_RESOURCE_ID'"]' \
			-s 'policies=["'$$EXCHANGE_POLICY_ID'"]' \
		)

.PHONY: te/setup
te/setup: te/enable-permissions te/add-policy te/add-permission ##@token Set up token exchange

.PHONY: te/exchange
te/exchange: ##@token Test by exchanging tokens
	@(TOKEN=`curl -X POST --header "Content-Type: application/x-www-form-urlencoded" \
			--data 'grant_type=password' \
			--data 'client_id=$(KC_PUBLIC_CLIENT)' \
			--data 'username=ecila' --data 'password=password' \
			http://localhost:8080/realms/$(KC_REALM)/protocol/openid-connect/token \
			| jq -r '.access_token'` \
			&& curl -sS --request POST --url http://localhost:8080/realms/$(KC_REALM)/protocol/openid-connect/token \
          --header 'Content-Type: application/x-www-form-urlencoded' \
          --data "client_id=$(KC_PUBLIC_CLIENT)" \
          --data "subject_token=$$TOKEN" \
          --data "audience=$(KC_INTERNAL_CLIENT)" \
          --data-urlencode "grant_type=urn:ietf:params:oauth:grant-type:token-exchange" \
          --data-urlencode "requested_token_type=urn:ietf:params:oauth:token-type:refresh_token" \
          | jq . \
	)

.PHONY: realm/delete
realm/delete: ##@realm Delete realm
	@($(DOCKER) exec -it $(APP) $(KC_ADM) \
		delete realms/$(KC_REALM) $(KC_ADM_CON) \
	)

### MISC

.PHONY: init
init: tls/create-cert network/create tls/trust-cert dns/insert## Initialize the environment by creating cert manager
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
