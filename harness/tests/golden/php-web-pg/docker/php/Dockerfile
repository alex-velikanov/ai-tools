# syntax=docker/dockerfile:1
# Tool container for PHP: runs phpunit, phpstan, composer and the Xdebug MCP for this project.
ARG PHP_VERSION=8.3
FROM php:${PHP_VERSION}-cli

COPY --from=ghcr.io/mlocati/php-extension-installer:2 /usr/bin/install-php-extensions /usr/local/bin/
RUN apt-get update \
 && apt-get install -y --no-install-recommends git unzip \
 && rm -rf /var/lib/apt/lists/* \
 && install-php-extensions @composer xdebug sockets pdo_pgsql

# Xdebug is trigger-only, so it costs nothing until a trace is requested. client_host is
# 127.0.0.1 because the debug client (the MCP) runs inside this same container.
RUN printf '%s\n' \
    'xdebug.mode=develop,debug,trace,profile' \
    'xdebug.start_with_request=trigger' \
    'xdebug.client_host=127.0.0.1' \
    'xdebug.client_port=9003' \
    > /usr/local/etc/php/conf.d/zz-xdebug-harness.ini

# The Xdebug MCP is baked into the image, so it is not a dependency of your project.
ENV COMPOSER_HOME=/opt/composer \
    COMPOSER_CACHE_DIR=/tmp/composer-cache \
    PATH="/opt/composer/vendor/bin:${PATH}"
RUN composer global require koriym/xdebug-mcp --no-interaction

RUN useradd --create-home --uid 1000 dev
USER dev
WORKDIR /app
