#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
fake_docker_dir="$repo_root/tests/fakes"
work_dir="${TMPDIR:-/tmp}/desktop-in-docker-fake-docker-test"
invalid_arch_x11_log="$work_dir/invalid-arch-x11.log"
invalid_ubuntu_x11_log="$work_dir/invalid-ubuntu-x11.log"
invalid_wayland_system_log="$work_dir/invalid-wayland-system.log"
invalid_wayland_desktop_log="$work_dir/invalid-wayland-desktop.log"
x11_start_log="$work_dir/docker-start-x11.log"
wayland_start_log="$work_dir/docker-start-wayland.log"
webtop_start_log="$work_dir/docker-start-webtop.log"

mkdir -p "$work_dir"
rm -f "$work_dir"/*.log "$work_dir"/*.out

run_with_fake_docker() {
    local log_file=$1
    shift

    PATH="$fake_docker_dir:$PATH" \
    FAKE_DOCKER_LOG="$log_file" \
    "$@"
}

assert_command_succeeds() {
    local log_file=$1
    shift
    local output_file="${log_file}.out"

    if ! run_with_fake_docker "$log_file" "$@" >"$output_file" 2>&1; then
        echo "Expected command to succeed: $*" >&2
        echo "--- $output_file ---" >&2
        cat "$output_file" >&2
        exit 1
    fi
}

assert_command_fails() {
    local log_file=$1
    local expected_output=$2
    shift 2
    local output_file="${log_file}.out"

    if run_with_fake_docker "$log_file" "$@" >"$output_file" 2>&1; then
        echo "Expected command to fail: $*" >&2
        echo "--- $output_file ---" >&2
        cat "$output_file" >&2
        exit 1
    fi

    if ! grep -Fq -- "$expected_output" "$output_file"; then
        echo "Expected command output to contain: $expected_output" >&2
        echo "--- $output_file ---" >&2
        cat "$output_file" >&2
        exit 1
    fi

    if [ -s "$log_file" ]; then
        echo "Expected no docker calls for failed command, got:" >&2
        cat "$log_file" >&2
        exit 1
    fi
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

default_system_version() {
    local system=$1

    case "$system" in
        debian) echo "trixie" ;;
        ubuntu) echo "noble" ;;
        fedora) echo "41" ;;
        arch|alpine) echo "latest" ;;
        *) echo "latest" ;;
    esac
}

expected_x11_desktop_dockerfile() {
    local system=$1
    local desktop=$2
    local dockerfile="docker/dockerfiles/${desktop}/${system}.Dockerfile"

    if [ -f "$dockerfile" ]; then
        echo "$dockerfile"
    else
        echo "docker/dockerfiles/${desktop}/debian.Dockerfile"
    fi
}

verify_build_combo() {
    local variant=$1
    local system=$2
    local desktop=$3
    local cn_mode=$4
    local version
    local log_file
    local merged_dockerfile
    local expected_desktop_dockerfile
    local expected_webtop_image

    version=$(default_system_version "$system")
    log_file="$work_dir/${variant}-${system}-${version}-${desktop}-${cn_mode#--}.log"

    echo "  - $variant / $system:$version / $desktop / $cn_mode"
    assert_command_succeeds "$log_file" \
        ./scripts/build-image.sh \
        --image-variant "$variant" \
        --system "$system" \
        --version "$version" \
        --desktop "$desktop" \
        --build \
        "$cn_mode"

    assert_log_contains "$log_file" "docker image prune -f"

    if [ "$variant" = "webtop" ]; then
        expected_webtop_image="lscr.io/linuxserver/webtop:${system}-${desktop}"
        if [ "$cn_mode" = "--cn-mirror" ]; then
            merged_dockerfile="build/webtop/${system}_cn.Dockerfile"
        else
            merged_dockerfile="build/webtop/${system}.Dockerfile"
        fi

        assert_log_line_count "$log_file" 1 "docker build "
        assert_log_contains "$log_file" "--build-arg WEBTOP_BASE_IMAGE=$expected_webtop_image"
        assert_log_contains "$log_file" "-f $merged_dockerfile"
        assert_log_not_contains "$log_file" "--build-arg BASE_IMAGE="
    elif [ "$variant" = "wayland" ]; then
        if [ "$cn_mode" = "--cn-mirror" ]; then
            merged_dockerfile="build/wayland/${system}_cn.Dockerfile"
        else
            merged_dockerfile="build/wayland/${system}.Dockerfile"
        fi

        assert_log_line_count "$log_file" 2 "docker build "
        assert_log_contains "$log_file" "--build-arg BASE_FROM_IMAGE=archlinux:$version"
        assert_log_contains "$log_file" "-f $merged_dockerfile"
        assert_log_contains "$log_file" "--build-arg BASE_IMAGE="
        assert_log_contains "$log_file" "-f docker/dockerfiles/wayland/${desktop}/${system}.Dockerfile"
    else
        if [ "$cn_mode" = "--cn-mirror" ]; then
            merged_dockerfile="build/x11/${system}_cn.Dockerfile"
        else
            merged_dockerfile="build/x11/${system}.Dockerfile"
        fi
        expected_desktop_dockerfile=$(expected_x11_desktop_dockerfile "$system" "$desktop")

        assert_log_line_count "$log_file" 2 "docker build "
        if [ "$system" = "arch" ]; then
            assert_log_contains "$log_file" "--build-arg BASE_FROM_IMAGE=archlinux:$version"
        else
            assert_log_contains "$log_file" "--build-arg BASE_FROM_IMAGE=${system}:$version"
        fi
        assert_log_contains "$log_file" "-f $merged_dockerfile"
        assert_log_contains "$log_file" "--build-arg BASE_IMAGE="
        assert_log_contains "$log_file" "-f $expected_desktop_dockerfile"
    fi
}

cd "$repo_root"

echo "Verifying invalid matrix failures..."
assert_command_fails "$invalid_arch_x11_log" "x11 does not support --system arch" ./scripts/build-image.sh -b -s arch --no-cn-mirror
assert_command_fails "$invalid_ubuntu_x11_log" "supports noble/24.04 or earlier only" ./scripts/build-image.sh -b -s ubuntu -v plucky --no-cn-mirror
assert_command_fails "$invalid_wayland_system_log" "wayland supports --system arch only" ./scripts/build-image.sh -b --image-variant wayland -s debian --no-cn-mirror
assert_command_fails "$invalid_wayland_desktop_log" "wayland supports --desktop weston only" ./scripts/build-image.sh -b --image-variant wayland -s arch -d xfce --no-cn-mirror

desktops=(xfce lxqt kde mate cinnamon lxde gnome enlightenment)
x11_systems=(debian ubuntu fedora alpine)
webtop_systems=(debian ubuntu fedora arch alpine)
cn_modes=(--no-cn-mirror --cn-mirror)
verified_combos=0

echo "Verifying all fake docker x11 build combinations..."
for system in "${x11_systems[@]}"; do
    for desktop in "${desktops[@]}"; do
        for cn_mode in "${cn_modes[@]}"; do
            verify_build_combo x11 "$system" "$desktop" "$cn_mode"
            ((verified_combos += 1))
        done
    done
done

echo "Verifying fake docker wayland build combination..."
verify_build_combo wayland arch weston --no-cn-mirror
((verified_combos += 1))

echo "Verifying all fake docker webtop build combinations..."
for system in "${webtop_systems[@]}"; do
    for desktop in "${desktops[@]}"; do
        for cn_mode in "${cn_modes[@]}"; do
            verify_build_combo webtop "$system" "$desktop" "$cn_mode"
            ((verified_combos += 1))
        done
    done
done

echo "Verifying fake docker x11 compose start path..."
assert_command_succeeds "$x11_start_log" ./scripts/build-image.sh --image-variant x11 --start --no-cn-mirror

assert_log_contains "$x11_start_log" "docker compose -f docker-compose.yml up -d --build"
assert_log_contains "$x11_start_log" "docker compose port desktop 6080"
assert_log_contains "$x11_start_log" "docker compose port desktop 5901"

echo "Verifying fake docker wayland compose start path..."
assert_command_succeeds "$wayland_start_log" ./scripts/build-image.sh --image-variant wayland --system arch --start --no-cn-mirror

assert_log_contains "$wayland_start_log" "docker compose -f docker-compose.yml up -d --build"
assert_log_contains "$wayland_start_log" "docker compose port desktop 3389"
assert_log_not_contains "$wayland_start_log" "docker compose port desktop 6080"
assert_log_not_contains "$wayland_start_log" "docker compose port desktop 5901"

echo "Verifying fake docker webtop compose start path..."
assert_command_succeeds "$webtop_start_log" ./scripts/build-image.sh --image-variant webtop --start --no-cn-mirror

assert_log_contains "$webtop_start_log" "docker compose -f docker-compose.yml up -d --build"
assert_log_contains "$webtop_start_log" "docker compose port desktop 3000"
assert_log_contains "$webtop_start_log" "docker compose port desktop 3001"

echo "Fake docker verification passed."
echo "Verified build combinations: $verified_combos"
echo "Logs: $work_dir"
