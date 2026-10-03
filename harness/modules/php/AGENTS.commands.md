Up:        docker compose up -d --build            # starts PHP{{DB_NOTE}} in containers; see compose.yaml
PHP test:  docker compose exec -T app vendor/bin/phpunit
PHP lint:  docker compose exec -T app vendor/bin/phpstan analyse -c phpstan.neon.dist   # start at level 6, raise one at a time
PHP shell: docker compose exec app bash
PHP trace: Xdebug MCP (`xtrace`) runs inside the app container; trace one entry point, never a whole request. Local dev only.
