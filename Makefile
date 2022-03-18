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
MFILECWD = $(shell pwd)
ETC=$(MFILECWD)/etc

#space separated string array ->
$(eval $(call defw,NAMESPACES,keycloak-test))
$(eval $(call defw,DEFAULT_NAMESPACE,$(shell echo $(NAMESPACES) | awk '{print $$1}')))
$(eval $(call defw,DOMAINS,"localhost.com api.localhost.com cache.localhost.com login.localhost.com www.localhost.com"))
$(eval $(call defw,CLUSTER_NAME,$(shell basename $(MFILECWD))))
$(eval $(call defw,IP_ADDRESS,$(shell hostname -I | awk '{print $$1}')))
$(eval $(call defw,KUBECTL,kubectl))
$(eval $(call defw,OPENSSL,openssl))
$(eval $(call defw,CA_TLS_FILE,$(ETC)/localhost-ca.pem))
$(eval $(call defw,CA_TLS_KEY,$(ETC)/localhost-ca-key.pem))
$(eval $(call defw,TLS_FILE,$(ETC)/server.pem))
$(eval $(call defw,TLS_KEY,$(ETC)/server-key.pem))
$(eval $(call defw,TLS_CSR,$(ETC)/server.csr))

MAIN_DOMAIN=$(shell echo $(DOMAINS) | awk '{print $$1}')
SAN=$(shell echo $(DOMAINS) | sed 's/[^ ]* */DNS:&/g' | sed 's/\s\+/,/g') 

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

.PHONY: tls/create-ca
tls/create-ca: ##@tls Create self sign CA certs
	@echo "Creating key"
	$(OPENSSL) genrsa -out $(CA_TLS_KEY) 4096
	$(OPENSSL) req -x509 -new -nodes -key $(CA_TLS_KEY) -sha256 -days 1024 -subj "/C=UK/ST=London/O=Issuing authority/OU=IT management" -out $(CA_TLS_FILE)
	@echo "Created at: $(CA_TLS_FILE)"

.PHONY: tls/create-cert
tls/create-cert: tls/create-ca ##@tls Create self sign certs for local machine
	@echo "Creating self signed certificate"
	$(OPENSSL) req -newkey rsa:2048 -nodes -keyout $(TLS_KEY) -subj "/C=UK/ST=London/L=London/O=Development/OU=IT/CN=$(MAIN_DOMAIN)" -out $(TLS_CSR)
	$(OPENSSL) x509 -req -extfile <(printf "subjectAltName=$(SAN),DNS:localhost,DNS:127.0.0.1") -days 365 -signkey $(CA_TLS_KEY) -in $(TLS_CSR) -out $(TLS_FILE)

.PHONY: tls/show-ca
tls/show-ca: ##@tls Show cert details
	@echo "Creating self signed certificate"
	$(OPENSSL) x509 -in $(CA_TLS_FILE) -text -noout

.PHONY: tls/show-cert
tls/show-cert: ##@tls Show cert details
	@echo "Creating self signed certificate"
	$(OPENSSL) x509 -in $(TLS_FILE) -text -noout

.PHONY: tls/trust-cert
tls/trust-cert: ##@tls Trust self signed cert by local browser
	@echo "Import self signed cert into user's truststore"
	@[ -d ~/.pki/nssdb ] || mkdir -p ~/.pki/nssdb
	@certutil -d sql:$$HOME/.pki/nssdb -A -n '$(MAIN_DOMAIN) cert authority' -i $(CA_TLS_FILE) -t TCP,TCP,TCP
	@certutil -d sql:$$HOME/.pki/nssdb -A -n '$(MAIN_DOMAIN)' -i $(TLS_FILE) -t P,P,P
	@echo "Import successful..."

### MISC

.PHONY: init
init: k8s/create-namespaces k8s/certman/install k8s/certman/secret k8s/certman/issuer k8s/certman/install-cert sampledata dns/insert## Initialize the environment by creating cert manager
	@echo "Init completed"

.PHONY: synctime
synctime: ##@misc Sync VM time
	@sudo sudo timedatectl set-ntp off
	@sudo timedatectl set-ntp on
	@date

.PHONY: versions
versions: ##@misc Print the "imporant" tools versions out for easier debugging.
	@echo "=== BEGIN Version Info ==="
	@echo "Project name: ${CLUSTER_NAME}"
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
