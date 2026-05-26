#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
fake_docker_dir="$repo_root/tests/fakes"
work_dir="${TMPDIR:-/tmp}/desktop-in-docker-fake-docker-test"
build_log="$work_dir/docker-build.log"
start_log="$work_dir/docker-start.log"
webtop_log="$work_dir/docker-webtop.log"
webtop_cn_log="$work_dir/docker-webtop-cn.log"

mkdir -p "$work_dir"
rm -f "$build_log" "$start_log" "$webtop_log" "$webtop_cn_log"

run_with_fake_docker() {
    local log_file=$1
    shift

    PATH="$fake_docker_dir:$PATH" \
    FAKE_DOCKER_LOG="$log_file" \
    "$@"
}

assert_log_contains() {
    local log_file=$1
    local expected=$2

    if ! grep -Fq -- "$expected" "$log_file"; then
        echo "Expected log to contain: $expected" >&2
        echo "--- $log_file ---" >&2
        cat "$log_file" >&2
        exit 1
    fi
}

assert_log_not_contains() {
    local log_file=$1
    local unexpected=$2

    if grep -Fq -- "$unexpected" "$log_file"; then
        echo "Expected log not to contain: $unexpected" >&2
        echo "--- $log_file ---" >&2
        cat "$log_file" >&2
        exit 1
    fi
}

assert_log_line_count() {
    local log_file=$1
    local expected=$2
    local pattern=$3
    local actual

    actual=$(grep -Fc -- "$pattern" "$log_file" || true)
    if [ "$actual" -ne "$expected" ]; then
        echo "Expected $expected occurrences of '$pattern', got $actual" >&2
        echo "--- $log_file ---" >&2
        cat "$log_file" >&2
        exit 1
    fi
}

cd "$repo_root"

echo "Verifying fake docker build path..."
run_with_fake_docker "$build_log" ./scripts/build-image.sh -b --no-cn-mirror

assert_log_contains "$build_log" "docker build"
assert_log_contains "$build_log" "--build-arg BASE_FROM_IMAGE=debian:trixie"
assert_log_contains "$build_log" "-f build/x11/debian.Dockerfile"
assert_log_contains "$build_log" "--build-arg BASE_IMAGE="
assert_log_contains "$build_log" "-f docker/dockerfiles/xfce/debian.Dockerfile"
assert_log_contains "$build_log" "docker image prune -f"

echo "Verifying fake docker webtop build path..."
run_with_fake_docker "$webtop_log" ./scripts/build-image.sh --image-variant webtop -s arch -d xfce -b --no-cn-mirror

assert_log_contains "$webtop_log" "docker build"
assert_log_contains "$webtop_log" "--build-arg WEBTOP_BASE_IMAGE=lscr.io/linuxserver/webtop:arch-xfce"
assert_log_contains "$webtop_log" "-f build/webtop/arch.Dockerfile"
assert_log_not_contains "$webtop_log" "-f build/webtop/arch_cn.Dockerfile"
assert_log_contains "$webtop_log" "docker image prune -f"

echo "Verifying fake docker webtop CN single-stage build path..."
run_with_fake_docker "$webtop_cn_log" ./scripts/build-image.sh --image-variant webtop -s debian -d xfce -b --cn-mirror

assert_log_line_count "$webtop_cn_log" 1 "docker build "
assert_log_contains "$webtop_cn_log" "--build-arg WEBTOP_BASE_IMAGE=lscr.io/linuxserver/webtop:debian-xfce"
assert_log_contains "$webtop_cn_log" "-f build/webtop/debian_cn.Dockerfile"
assert_log_not_contains "$webtop_cn_log" "--build-arg WEBTOP_IMAGE="
assert_log_contains "$webtop_cn_log" "docker image prune -f"

echo "Verifying fake docker compose start path..."
run_with_fake_docker "$start_log" ./scripts/build-image.sh -S --no-cn-mirror

assert_log_contains "$start_log" "docker compose -f docker-compose.yml up -d --build"
assert_log_contains "$start_log" "docker compose port desktop 6080"
assert_log_contains "$start_log" "docker compose port desktop 5901"

echo "Fake docker verification passed."
echo "Build log: $build_log"
echo "Start log: $start_log"
