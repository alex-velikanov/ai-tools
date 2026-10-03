# Commands
Up:        docker compose up -d --build            # starts PHP, mysql in containers; see compose.yaml
PHP test:  docker compose exec -T app vendor/bin/phpunit
PHP lint:  docker compose exec -T app vendor/bin/phpstan analyse -c phpstan.neon.dist   # start at level 6, raise one at a time
PHP shell: docker compose exec app bash
PHP trace: Xdebug MCP (`xtrace`) runs inside the app container; trace one entry point, never a whole request. Local dev only.
DB shell:  docker compose exec db mysql -uapp -pdev app

# Structure
TODO: where domain logic, HTTP layer, and tests live; what each directory is for.

# Rules
TODO: only add a rule after an agent makes the same mistake twice. Keep this file under ~150 lines.

# CI
Check CI with `gh pr checks <n>`, then `gh run view <id> --log-failed`.
Never fetch full logs — 30k+ lines of setup noise.
