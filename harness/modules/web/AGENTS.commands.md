Web dev:    docker compose up -d web               # http://localhost:5173 (dev server runs in a container)
Web build:  docker compose exec -T web npm run build
Web e2e:    cd e2e && npx playwright test          # runs on the host against the running dev server
Visual reg: vr/vr.sh --record <base-url>           # baseline the known-good build; edit vr/pages.json first
            vr/vr.sh <base-url>                    # compare to that baseline; open vr/report/index.html
            vr/vr.sh --discover <base-url>         # list linked/sitemap pages missing from pages.json (changes nothing)
