FROM quay.io/keycloak/keycloak:18.0.0 as builder

ARG KC_METRICS_ENABLED=false
ARG KC_FEATURES=
ARG KC_DB=postgres

ENV KC_METRICS_ENABLED=$KC_METRICS_ENABLED
ENV KC_FEATURES=$KC_FEATURES
ENV KC_DB=$KC_DB

# see https://www.keycloak.org/server/all-config for config variables
RUN /opt/keycloak/bin/kc.sh build && /opt/keycloak/bin/kc.sh show-config

FROM quay.io/keycloak/keycloak:17.0.1
COPY --from=builder /opt/keycloak/lib/quarkus/ /opt/keycloak/lib/quarkus/
WORKDIR /opt/keycloak
ENTRYPOINT ["/opt/keycloak/bin/kc.sh", "start"]
