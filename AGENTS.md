# Base44 Environment Setup — Stripe Ruby SDK

## Project Overview
This is the **stripe-ruby** gem — the official Stripe Ruby SDK library (v20.0.0).
It is a Ruby gem library, not a web application. There is no web frontend or API server.

## How It Runs Here
Since the project is a library (not a web app), a lightweight dashboard (`base44/dashboard.rb`)
serves on port 3000 using WEBrick. It runs the full test suite via `bundle exec rake test`
in a background thread and displays the results.

## Architecture
- **Dockerfile.base44**: Ruby 3.3-slim + git + build-essential + stripe-mock binary
- **docker-compose.base44.yml**: Single `app` service, bind-mounts the repo, starts stripe-mock
  in the background, runs `bundle install`, then starts the dashboard
- **base44/dashboard.rb**: WEBrick web server that runs the test suite and serves results

## Key Dependencies
- **stripe-mock** (v0.206.0): Mock Stripe API server required by the test suite. Downloaded
  as a pre-built binary in the Dockerfile. Started in the background on port 12111.
- **Ruby >= 3.0.0**: Required by the gemspec. Using Ruby 3.3-slim.
- **build-essential + git**: Needed for native gem extension compilation and the gemspec's
  `git ls-files` call during `bundle install`.
- **webrick**: Not bundled with Ruby 3.3+, installed via `gem install webrick` in the Dockerfile.

## Test Suite
- 72 test files, ~2100 tests using Test::Unit + shoulda-context + webmock + mocha
- All HTTP calls are mocked via webmock, redirecting to stripe-mock
- No external credentials needed — all tests run against the local stripe-mock
- Run manually: `docker compose -f docker-compose.base44.yml exec app bundle exec rake test`

## No External Secrets Required
The test suite uses stripe-mock for all API calls. No Stripe API keys or webhook secrets
are needed to run the project or its tests.

## Verification
- Health check: `GET /health` returns `{"status":"ok"}`
- Dashboard: `GET /` shows test results with pass/fail counts
- Container health: `docker compose -f docker-compose.base44.yml ps`
