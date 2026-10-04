# Commands
Up:        docker compose up -d --build            # starts PHP, Node, postgres in containers; see compose.yaml
PHP test:  docker compose exec -T app vendor/bin/phpunit
PHP lint:  docker compose exec -T app vendor/bin/phpstan analyse -c phpstan.neon.dist   # start at level 6, raise one at a time
PHP shell: docker compose exec app bash
PHP trace: Xdebug MCP (`xtrace`) runs inside the app container; trace one entry point, never a whole request. Local dev only.
Web dev:    docker compose up -d web               # http://localhost:5173 (dev server runs in a container)
Web build:  docker compose exec -T web npm run build
Web e2e:    cd e2e && npx playwright test          # runs on the host against the running dev server
Visual reg: vr/vr.sh --record <base-url>           # baseline the known-good build; edit vr/pages.json first
            vr/vr.sh <base-url>                    # compare the build under test to that baseline
            vr/vr.sh --discover <base-url>         # list linked/sitemap pages missing from pages.json (changes nothing)
DB shell:  docker compose exec db psql -U app app

# Structure
TODO: where domain logic, HTTP layer, and tests live; what each directory is for.

# Rules
TODO: only add a rule after an agent makes the same mistake twice. Keep this file under ~150 lines.

# CI
Check CI with `gh pr checks <n>`, then `gh run view <id> --log-failed`.
Never fetch full logs — 30k+ lines of setup noise.
