#!/usr/bin/env bash
set -euo pipefail

cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.."
mode=${READER_E2E_MODE:-integration}
case "$mode" in
  integration|checks|backend-unit|failure-check) ;;
  *) echo 'READER_E2E_MODE must be integration, checks, backend-unit or failure-check' >&2; exit 2 ;;
esac
if [[ $# -gt 1 || ( $# -eq 1 && $1 != --verify ) ]]; then
  echo 'Only --verify is accepted; endpoint/project/command overrides are forbidden' >&2
  exit 2
fi

project="libnode-reader-e2e-$(od -An -N12 -tx1 /dev/urandom | tr -d ' \n')"
docker_command() {
  env -i PATH="$PATH" HOME="$HOME" docker --context default "$@"
}
compose() {
  docker_command compose -p "$project" --env-file .env.verify.example \
    -f docker-compose.yml -f docker-compose.verify.yml --profile reader-e2e "$@"
}
assert_no_resources() {
  local containers networks volumes
  containers=$(docker_command ps -aq --filter "label=com.docker.compose.project=$project") || return 1
  networks=$(docker_command network ls -q --filter "label=com.docker.compose.project=$project") || return 1
  volumes=$(docker_command volume ls -q --filter "label=com.docker.compose.project=$project") || return 1
  [[ -z $containers && -z $networks && -z $volumes ]]
}
stage() {
  local label=$1
  shift
  echo "Reader stage: $label START"
  if ! "$@" >/dev/null 2>&1; then
    echo "Reader stage: $label FAIL" >&2
    exit 1
  fi
  echo "Reader stage: $label PASS"
}

if ! assert_no_resources; then
  echo 'Reader project collision/resource check failed; nothing started or cleaned' >&2
  exit 1
fi
stage capabilities docker_command buildx version
stage config compose config --quiet
if [[ ${1:-} == --verify ]]; then
  echo 'Reader config: PASS (example-only, quiet validation)'
  exit 0
fi

cleanup() {
  local status=$? cleanup_status=0
  trap - EXIT INT TERM
  compose down --volumes --remove-orphans --timeout 10 >/dev/null 2>&1 || cleanup_status=1
  assert_no_resources || cleanup_status=1
  if [[ $cleanup_status -ne 0 ]]; then
    echo "Reader cleanup: FAIL ($project)" >&2
    exit 1
  fi
  echo "Reader cleanup: PASS ($project; containers=0 networks=0 volumes=0)"
  exit "$status"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

echo "Reader mode: $mode ($project)"
case "$mode" in
  backend-unit)
    stage build-backend compose build reader-e2e-migrate
    output=''
    status=0
    summary_found=0
    output=$(compose run --rm --no-deps reader-e2e-migrate dotnet test \
      LibNode.Api.Tests/LibNode.Api.Tests.csproj --no-restore --configuration Release \
      --filter FullyQualifiedName~LibNode.Api.Tests.Unit.CollectionServiceTests --verbosity quiet 2>&1) || status=$?
    # Test summary only, never raw diagnostics or application logs.
    while IFS= read -r line; do
      if [[ $line =~ ^(Passed!|Failed!).*Failed:[[:space:]]+([0-9]+),[[:space:]]+Passed:[[:space:]]+([0-9]+),[[:space:]]+Skipped:[[:space:]]+([0-9]+),[[:space:]]+Total:[[:space:]]+([0-9]+) ]]; then
        summary_found=1
        echo "Reader collection unit: failed=${BASH_REMATCH[2]} passed=${BASH_REMATCH[3]} skipped=${BASH_REMATCH[4]} total=${BASH_REMATCH[5]}"
        if [[ ${BASH_REMATCH[4]} -ne 0 || ${BASH_REMATCH[5]} -lt 8 ]]; then status=1; fi
      fi
    done <<< "$output"
    if [[ $summary_found -ne 1 ]]; then
      echo 'Reader collection unit: FAIL (nonzero test inventory not proven)' >&2
      status=1
    fi
    echo "Reader stage: collection-unit exit=$status"
    exit "$status"
    ;;
  checks)
    stage build-checks compose build reader-e2e-web-checks reader-e2e-runner
    stage frontend-offline compose run --rm --no-deps reader-e2e-web-checks
    stage runner-guard compose run --rm --no-deps -e "TEST_READER_PROJECT=$project" reader-e2e-runner \
      node /app/reader-e2e/run-reader-e2e.cjs --self-check
    exit 0
    ;;
esac

stage build-apps compose build reader-e2e-migrate reader-e2e-api reader-e2e-web reader-e2e-runner
stage postgres compose up --wait --wait-timeout 120 --no-deps postgres-reader-verify
stage migration compose run --rm --no-deps reader-e2e-migrate
stage apps compose up -d --no-deps reader-e2e-api reader-e2e-web
status=0
output=$(compose run --rm --no-deps -e "READER_E2E_MODE=$mode" \
  -e "TEST_READER_PROJECT=$project" reader-e2e-runner 2>&1) || status=$?
# Only runner's strict static reporting grammar is shared. Do not expose Compose
# output, Playwright call logs, response bodies or browser diagnostics.
while IFS= read -r line; do
  if [[ $line =~ ^READER\ (PASS|FAIL|SUMMARY|EXPECTED_FAILURE)\ [a-z0-9_=-]+(\ [a-z0-9_=-]+)*$ ]]; then
    echo "$line"
  fi
done <<< "$output"
if [[ $mode == failure-check ]]; then
  if [[ $status -eq 42 && $output == *'READER EXPECTED_FAILURE post_fixture_exit=42'* ]]; then
    echo 'Reader failure-check: PASS (post-fixture exit 42; cleanup required)'
    exit 0
  fi
  echo 'Reader failure-check: FAIL (expected fixture marker/exit missing)' >&2
  exit 1
fi
if [[ $status -eq 0 && $output != *'READER SUMMARY ui=18 api=5 infra=2 skipped=0 page_errors=0'* ]]; then
  echo 'Reader integration: FAIL (complete scenario inventory not proven)' >&2
  exit 1
fi
exit "$status"
