#!/bin/bash
# Smoke and integration tests for photogimpmac.sh.
# All operations run inside isolated temp directories using mocked GIMP/curl/pgrep binaries.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
TARGET_SCRIPT="$SCRIPT_DIR/photogimpmac.sh"
BASH_BIN="${BASH_UNDER_TEST:-bash}"

PASS_COUNT=0
FAIL_COUNT=0
TEST_ROOT=""

cleanup() {
    if [ -n "${TEST_ROOT:-}" ] && [ -d "$TEST_ROOT" ]; then
        rm -rf "$TEST_ROOT"
    fi
}
trap cleanup EXIT

TEST_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/photogimp-tests.XXXXXX")"

fail() {
    echo "FAIL: $*" >&2
    FAIL_COUNT=$((FAIL_COUNT + 1))
}

pass() {
    echo "PASS: $*"
    PASS_COUNT=$((PASS_COUNT + 1))
}

assert_eq() {
    local expected="$1"
    local actual="$2"
    local msg="$3"
    if [ "$expected" = "$actual" ]; then
        pass "$msg"
    else
        fail "$msg (expected '$expected', got '$actual')"
    fi
}

assert_contains() {
    local haystack="$1"
    local needle="$2"
    local msg="$3"
    if printf '%s\n' "$haystack" | grep -Fq -- "$needle"; then
        pass "$msg"
    else
        fail "$msg (missing '$needle')"
    fi
}

make_mock_gimp() {
    local path="$1"
    local version_str="$2"
    mkdir -p "$(dirname "$path")"
    cat >"$path" <<EOF
#!/bin/bash
if [ "\${1:-}" = "--version" ]; then
    echo "GNU Image Manipulation Program version $version_str"
    exit 0
fi
exit 0
EOF
    chmod +x "$path"
}

make_zip_from_dir() {
    local src_dir="$1"
    local zip_path="$2"
    mkdir -p "$(dirname "$zip_path")"
    (
        cd "$src_dir" && zip -q -r "$zip_path" .
    )
}

run_syntax_check() {
    if "$BASH_BIN" -n "$TARGET_SCRIPT"; then
        pass "bash -n syntax check ($BASH_BIN)"
    else
        fail "bash -n syntax check ($BASH_BIN)"
    fi
}

test_help_and_version() {
    local out
    out="$("$BASH_BIN" "$TARGET_SCRIPT" --help)"
    assert_contains "$out" "Usage:" "--help prints usage"
    assert_contains "$out" "--dry-run" "--help lists --dry-run"

    out="$("$BASH_BIN" "$TARGET_SCRIPT" --version)"
    assert_contains "$out" "photogimpmac.sh" "--version prints script name"

    if "$BASH_BIN" "$TARGET_SCRIPT" --unknown-flag >/dev/null 2>&1; then
        fail "unknown flag should exit non-zero"
    else
        pass "unknown flag exits non-zero"
    fi

    if "$BASH_BIN" "$TARGET_SCRIPT" --zip /tmp/a.zip --download >/dev/null 2>&1; then
        fail "--zip and --download together should exit non-zero"
    else
        pass "--zip and --download mutually exclusive"
    fi
}

test_dry_run_and_install_gimp_30() {
    local case_dir="$TEST_ROOT/case_30"
    local fake_home="$case_dir/home with spaces"
    local gimp_bin="$case_dir/bin/gimp"
    local profile_dir="$fake_home/Library/Application Support/GIMP/3.0"
    local downloads_dir="$fake_home/Downloads"
    local zip_src="$case_dir/zip_src"

    make_mock_gimp "$gimp_bin" "3.0.2"
    mkdir -p "$profile_dir" "$downloads_dir"
    echo "orig_gimprc" >"$profile_dir/gimprc"

    mkdir -p "$zip_src/PhotoGIMP-master/.config/GIMP/3.0/splashes"
    echo "photogimp_gimprc" >"$zip_src/PhotoGIMP-master/.config/GIMP/3.0/gimprc"
    echo "splash" >"$zip_src/PhotoGIMP-master/.config/GIMP/3.0/splashes/photogimp.png"
    echo "dotfile_val" >"$zip_src/PhotoGIMP-master/.config/GIMP/3.0/.photogimp_marker"
    make_zip_from_dir "$zip_src" "$downloads_dir/PhotoGIMP-master.zip"

    # Dry run must not modify profile or create backups
    local dry_out
    dry_out="$(HOME="$fake_home" "$BASH_BIN" "$TARGET_SCRIPT" --dry-run --gimp-bin "$gimp_bin" --skip-running-check)"
    assert_contains "$dry_out" "[dry-run] No files were modified." "dry-run reports no modification"
    assert_eq "orig_gimprc" "$(cat "$profile_dir/gimprc")" "dry-run preserves original gimprc"
    local backup_count
    backup_count=$(find "$fake_home/Library/Application Support/GIMP" -maxdepth 1 -name "GIMP-backup-*" | wc -l | tr -d ' ')
    assert_eq "0" "$backup_count" "dry-run does not create backup directory"

    # Real install (using mocked HOME, never real HOME)
    local run_out
    run_out="$(HOME="$fake_home" "$BASH_BIN" "$TARGET_SCRIPT" --gimp-bin "$gimp_bin" --skip-running-check)"
    assert_contains "$run_out" "Done! Launch GIMP to start using PhotoGIMP." "GIMP 3.0 install completes"
    assert_eq "photogimp_gimprc" "$(cat "$profile_dir/gimprc")" "GIMP 3.0 gimprc updated"
    assert_eq "splash" "$(cat "$profile_dir/splashes/photogimp.png")" "GIMP 3.0 nested splash installed"
    assert_eq "dotfile_val" "$(cat "$profile_dir/.photogimp_marker")" "GIMP 3.0 dotfile installed"

    local backup_dir
    backup_dir=$(find "$fake_home/Library/Application Support/GIMP" -maxdepth 1 -type d -name "GIMP-backup-*" | head -n 1)
    if [ -n "$backup_dir" ] && [ "$(cat "$backup_dir/3.0/gimprc")" = "orig_gimprc" ]; then
        pass "GIMP 3.0 backup preserved original config"
    else
        fail "GIMP 3.0 backup missing or invalid"
    fi
}

test_gimp_32_with_release_30_layout() {
    local case_dir="$TEST_ROOT/case_32"
    local fake_home="$case_dir/home"
    local gimp_bin="$case_dir/bin/gimp"
    local profile_dir="$fake_home/Library/Application Support/GIMP/3.2"
    local zip_src="$case_dir/zip_src"
    local zip_path="$case_dir/PhotoGIMP.zip"

    make_mock_gimp "$gimp_bin" "3.2.0"
    mkdir -p "$profile_dir"
    echo "orig_32" >"$profile_dir/gimprc"

    mkdir -p "$zip_src/3.0"
    echo "photogimp_30_for_32" >"$zip_src/3.0/gimprc"
    make_zip_from_dir "$zip_src" "$zip_path"

    HOME="$fake_home" "$BASH_BIN" "$TARGET_SCRIPT" --gimp-bin "$gimp_bin" --zip "$zip_path" --skip-running-check >/dev/null
    assert_eq "photogimp_30_for_32" "$(cat "$profile_dir/gimprc")" "GIMP 3.2 uses 3.0 config fallback cleanly"
}

test_gimp_210_and_mismatch_rejection() {
    local case_dir="$TEST_ROOT/case_210"
    local fake_home="$case_dir/home"
    local gimp_210="$case_dir/bin/gimp-2.10"
    local gimp_30="$case_dir/bin/gimp-3.0"
    local profile_210="$fake_home/Library/Application Support/GIMP/2.10"
    local profile_30="$fake_home/Library/Application Support/GIMP/3.0"

    make_mock_gimp "$gimp_210" "2.10.38"
    make_mock_gimp "$gimp_30" "3.0.0"
    mkdir -p "$profile_210" "$profile_30"
    echo "orig_210" >"$profile_210/gimprc"
    echo "orig_30" >"$profile_30/gimprc"

    local zip_210_src="$case_dir/zip_210_src"
    local zip_210="$case_dir/PhotoGIMP-2.10.zip"
    mkdir -p "$zip_210_src/.config/GIMP/2.10"
    echo "photogimp_210" >"$zip_210_src/.config/GIMP/2.10/gimprc"
    make_zip_from_dir "$zip_210_src" "$zip_210"

    local zip_30_src="$case_dir/zip_30_src"
    local zip_30="$case_dir/PhotoGIMP-3.0.zip"
    mkdir -p "$zip_30_src/.config/GIMP/3.0"
    echo "photogimp_30" >"$zip_30_src/.config/GIMP/3.0/gimprc"
    make_zip_from_dir "$zip_30_src" "$zip_30"

    # Valid 2.10 install
    HOME="$fake_home" "$BASH_BIN" "$TARGET_SCRIPT" --gimp-bin "$gimp_210" --zip "$zip_210" --skip-running-check >/dev/null
    assert_eq "photogimp_210" "$(cat "$profile_210/gimprc")" "GIMP 2.10 config installed"

    # Mismatch: 3.0 binary + 2.10 zip must fail without touching 3.0 profile
    if HOME="$fake_home" "$BASH_BIN" "$TARGET_SCRIPT" --gimp-bin "$gimp_30" --zip "$zip_210" --skip-running-check >/dev/null 2>&1; then
        fail "GIMP 3.0 should reject 2.10-only archive"
    else
        pass "GIMP 3.0 rejects 2.10-only archive"
    fi
    assert_eq "orig_30" "$(cat "$profile_30/gimprc")" "rejected 2.10 archive leaves 3.0 profile untouched"

    # Mismatch: 2.10 binary + 3.0 zip must fail without touching 2.10 profile
    if HOME="$fake_home" "$BASH_BIN" "$TARGET_SCRIPT" --gimp-bin "$gimp_210" --zip "$zip_30" --skip-running-check >/dev/null 2>&1; then
        fail "GIMP 2.10 should reject 3.0-only archive"
    else
        pass "GIMP 2.10 rejects 3.0-only archive"
    fi
    assert_eq "photogimp_210" "$(cat "$profile_210/gimprc")" "rejected 3.0 archive leaves 2.10 profile untouched"
}

test_error_handling_and_download() {
    local case_dir="$TEST_ROOT/case_errors"
    local fake_home="$case_dir/home"
    local gimp_bin="$case_dir/bin/gimp"
    local custom_cfg="$case_dir/custom_cfg"
    local mock_bin="$case_dir/mock_bin"

    make_mock_gimp "$gimp_bin" "3.0.1"
    mkdir -p "$fake_home/Downloads" "$mock_bin"

    # Missing profile dir should fail
    if HOME="$fake_home" "$BASH_BIN" "$TARGET_SCRIPT" --gimp-bin "$gimp_bin" --config-dir "$case_dir/does_not_exist" --skip-running-check >/dev/null 2>&1; then
        fail "missing config dir should fail"
    else
        pass "missing config dir fails cleanly"
    fi

    mkdir -p "$custom_cfg"
    echo "orig_custom" >"$custom_cfg/gimprc"

    # Corrupt zip should fail
    echo "not-a-zip" >"$case_dir/corrupt.zip"
    if HOME="$fake_home" "$BASH_BIN" "$TARGET_SCRIPT" --gimp-bin "$gimp_bin" --config-dir "$custom_cfg" --zip "$case_dir/corrupt.zip" --skip-running-check >/dev/null 2>&1; then
        fail "corrupt zip should fail"
    else
        pass "corrupt zip fails cleanly"
    fi

    # Mocked failing curl should fail cleanly
    cat >"$mock_bin/curl" <<'EOF'
#!/bin/bash
exit 22
EOF
    chmod +x "$mock_bin/curl"

    if PATH="$mock_bin:$PATH" HOME="$fake_home" "$BASH_BIN" "$TARGET_SCRIPT" --gimp-bin "$gimp_bin" --config-dir "$custom_cfg" --download --skip-running-check >/dev/null 2>&1; then
        fail "failing curl should fail"
    else
        pass "failing curl fails cleanly"
    fi

    # Mocked succeeding curl should download & install
    local dl_src="$case_dir/dl_src"
    local dl_zip="$case_dir/dl_fixture.zip"
    mkdir -p "$dl_src/.config/GIMP/3.0"
    echo "downloaded_gimprc" >"$dl_src/.config/GIMP/3.0/gimprc"
    make_zip_from_dir "$dl_src" "$dl_zip"

    cat >"$mock_bin/curl" <<EOF
#!/bin/bash
out=""
while [ "\$#" -gt 0 ]; do
    if [ "\$1" = "-o" ]; then
        out="\$2"
        shift 2
    else
        shift
    fi
done
cp "$dl_zip" "\$out"
EOF
    chmod +x "$mock_bin/curl"

    PATH="$mock_bin:$PATH" HOME="$fake_home" "$BASH_BIN" "$TARGET_SCRIPT" \
        --gimp-bin "$gimp_bin" --config-dir "$custom_cfg" --download --no-backup --skip-running-check >/dev/null
    assert_eq "downloaded_gimprc" "$(cat "$custom_cfg/gimprc")" "--download installs archive via curl"

    # Running GIMP check with mocked pgrep
    cat >"$mock_bin/pgrep" <<'EOF'
#!/bin/bash
exit 0
EOF
    chmod +x "$mock_bin/pgrep"

    if PATH="$mock_bin:$PATH" HOME="$fake_home" "$BASH_BIN" "$TARGET_SCRIPT" \
        --gimp-bin "$gimp_bin" --config-dir "$custom_cfg" --zip "$dl_zip" >/dev/null 2>&1; then
        fail "running GIMP check should abort when pgrep matches"
    else
        pass "running GIMP check aborts when GIMP is running"
    fi
}

main() {
    run_syntax_check
    test_help_and_version
    test_dry_run_and_install_gimp_30
    test_gimp_32_with_release_30_layout
    test_gimp_210_and_mismatch_rejection
    test_error_handling_and_download

    echo ""
    echo "Results: $PASS_COUNT passed, $FAIL_COUNT failed"
    [ "$FAIL_COUNT" -eq 0 ]
}

main "$@"
