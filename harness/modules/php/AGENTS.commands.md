PHP test:  cd {{PHP_DIR}} && vendor/bin/phpunit
PHP lint:  cd {{PHP_DIR}} && vendor/bin/phpstan analyse -c phpstan.neon.dist   # start at level 6, raise one at a time
PHP trace: Xdebug MCP (`xtrace`) — trace one entry point, never a whole request. Local dev only.
