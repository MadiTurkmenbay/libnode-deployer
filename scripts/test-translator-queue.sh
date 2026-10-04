#!/usr/bin/env bash
set -euo pipefail

cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.."
mode=${QUEUE_TEST_MODE:-integration}
case "$mode" in
  integration|offline|checks|failure-check) ;;
  *) echo 'QUEUE_TEST_MODE must be integration, offline, checks or failure-check' >&2; exit 2 ;;
esac
if [[ $# -gt 1 || ( $# -eq 1 && $1 != --verify ) ]]; then
  echo 'Only --verify is accepted; arbitrary command/project overrides are forbidden' >&2
  exit 2
fi

# Shell/Make/Compose project and endpoint overrides cannot enter this command.
project="libnode-translator-queue-$(od -An -N12 -tx1 /dev/urandom | tr -d ' \n')"
docker_command() {
  env -i PATH="$PATH" HOME="$HOME" docker "$@"
}
compose() {
  docker_command compose \
    -p "$project" --env-file .env.verify.example \
    -f docker-compose.yml -f docker-compose.verify.yml \
    --profile translator-queue-tests "$@"
}
assert_no_resources() {
  local containers networks volumes
  containers=$(docker_command ps -aq --filter "label=com.docker.compose.project=$project") || return 1
  networks=$(docker_command network ls -q --filter "label=com.docker.compose.project=$project") || return 1
  volumes=$(docker_command volume ls -q --filter "label=com.docker.compose.project=$project") || return 1
  [[ -z $containers && -z $networks && -z $volumes ]]
}

# Do not claim or clean a project with pre-existing resources, even on collision.
if ! assert_no_resources; then
  echo 'Disposable project collision/resource check failed; nothing was started or cleaned' >&2
  exit 1
fi
compose config --quiet
if [[ ${1:-} == --verify ]]; then
  echo 'Queue test Compose config: PASS (example-only, quiet validation)'
  exit 0
fi

cleanup() {
  local status=$? cleanup_status=0
  trap - EXIT INT TERM
  compose down --volumes --remove-orphans --timeout 10 >/dev/null 2>&1 || cleanup_status=1
  assert_no_resources || cleanup_status=1
  if [[ $cleanup_status -ne 0 ]]; then
    echo "Scoped cleanup: FAIL ($project)" >&2
    exit 1
  fi
  echo "Scoped cleanup: PASS ($project; containers/networks/volumes absent)"
  exit "$status"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

echo "Queue test mode: $mode ($project)"
compose build translator-tests
if [[ $mode == integration || $mode == failure-check ]]; then
  compose up --wait --wait-timeout 120 --no-deps postgres-translator-verify redis-verify
fi
status=0
compose run --rm --no-deps -e "QUEUE_TEST_MODE=$mode" translator-tests || status=$?
if [[ $mode == failure-check && $status -eq 42 ]]; then
  echo 'Intentional post-migration exit 42 reached: PASS (cleanup still required)'
  exit 0
fi
if [[ $mode == failure-check && $status -eq 0 ]]; then
  echo 'Failure self-check did not reach the required exit 42' >&2
  exit 1
fi
exit "$status"
