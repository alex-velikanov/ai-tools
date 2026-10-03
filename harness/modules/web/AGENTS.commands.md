Web dev:    docker compose up -d web               # http://localhost:5173 (dev server runs in a container)
Web build:  docker compose exec -T web npm run build
Web e2e:    cd e2e && npx playwright test          # runs on the host against the running dev server
Visual reg: vr/vr.sh <base-url>                    # run before and after a deploy; edit vr/pages.json first
