ARG BASE_IMAGE=quay.io/keycloak/keycloak:20.0.3
ARG MAVEN_IMAGE=maven:3.8.6-jdk-11-slim
ARG KC_METRICS_ENABLED=true
ARG KC_HEALTH_ENABLED=true
ARG KC_FEATURES=
ARG KC_DB=postgres
ARG KC_SPI_THEME_DEFAULT=keycloak
ARG KC_HTTP_RELATIVE_PATH=/auth
ARG KC_CACHE=ispn

FROM $MAVEN_IMAGE as providers

RUN apt-get update -y && apt-get -y install  git
WORKDIR /usr/src/app
COPY . .
RUN mvn package -Dmaven.test.skip

FROM $BASE_IMAGE as builder


ARG KC_METRICS_ENABLED
ARG KC_HEALTH_ENABLED
ARG KC_FEATURES
ARG KC_DB
ARG KC_SPI_THEME_DEFAULT
ARG KC_HTTP_RELATIVE_PATH
ARG KC_CACHE

ENV KC_METRICS_ENABLED=$KC_METRICS_ENABLED
ENV KC_HEALTH_ENABLED=$KC_HEALTH_ENABLED
ENV KC_FEATURES=$KC_FEATURES
ENV KC_DB=$KC_DB
ENV KC_VERSION=$KC_VERSION
ENV KC_CACHE=$KC_CACHE
ENV KC_SPI_THEME_DEFAULT=$KC_SPI_THEME_DEFAULT
ENV KC_HTTP_RELATIVE_PATH=$KC_HTTP_RELATIVE_PATH

COPY --from=providers /usr/src/app/themes/src/main/resources/themes /opt/keycloak/themes

# see https://www.keycloak.org/server/all-config for config variables
RUN /opt/keycloak/bin/kc.sh build && /opt/keycloak/bin/kc.sh show-config

FROM $BASE_IMAGE
ARG KC_SPI_THEME_DEFAULT
ENV KC_SPI_THEME_DEFAULT=$KC_SPI_THEME_DEFAULT

COPY --from=builder /opt/keycloak/lib/quarkus/ /opt/keycloak/lib/quarkus/
WORKDIR /opt/keycloak
ENTRYPOINT ["/opt/keycloak/bin/kc.sh"]
CMD ["start", "--optimized", "--log-level=INFO,org.keycloak:debug"]

