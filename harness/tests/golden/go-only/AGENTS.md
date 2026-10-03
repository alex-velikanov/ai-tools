# Commands
Go test:  cd svc && go test -race ./...
Go vet:   cd svc && go vet ./...
Go debug: try `dlv` / `go tool pprof` through the shell before adding any debugger MCP.

# Structure
TODO: where domain logic, HTTP layer, and tests live; what each directory is for.

# Rules
TODO: only add a rule after an agent makes the same mistake twice. Keep this file under ~150 lines.

# CI
Check CI with `gh pr checks <n>`, then `gh run view <id> --log-failed`.
Never fetch full logs — 30k+ lines of setup noise.
