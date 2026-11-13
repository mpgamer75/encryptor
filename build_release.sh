#!/usr/bin/env bash
# ==============================================================================
# Builds the release artifacts into dist/ :
#
#   encryptor_<version>-1_all.deb     Debian package
#   encryptor-<version>.tar.gz        source tarball (git archive of HEAD)
#   SHA256SUMS                        checksums of the two files above
#
#   ./build_release.sh            build from the current commit
#   ./build_release.sh v3.0.0     additionally require that the tag matches
#
# Used by .github/workflows/release.yml (publishing) and by CI on every push
# (dry run), so the release path is exercised long before a tag exists.
# ==============================================================================
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")"
expected_tag="${1:-}"

version="$(sed -n 's/^readonly ENCRYPTOR_VERSION="\(.*\)"$/\1/p' encryptor.sh)"
[[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "cannot read a valid version from encryptor.sh" >&2; exit 1; }
echo "Version: $version"

if [[ -n "$expected_tag" && "$expected_tag" != "v$version" ]]; then
    echo "tag $expected_tag does not match program version v$version" >&2; exit 1
fi

# Every place that states the version must agree before anything is built.
fail=0
check_version() {
    local file="$1" pattern="$2"
    if ! grep -Eq -- "$pattern" "$file"; then
        echo "version mismatch: $file does not contain /$pattern/" >&2; fail=1
    fi
}
v_re="${version//./\\.}"
check_version encryptor.spec    "^Version:[[:space:]]+${v_re}\$"
check_version debian/control    "^Version: ${v_re}-1\$"
check_version debian/changelog  "^encryptor \\(${v_re}-1\\) "
check_version Dockerfile        "image\\.version=\"${v_re}\""
check_version man/encryptor.1   "\"Encryptor ${v_re}\""
check_version README.md         "Version-${v_re}-"
check_version CHANGELOG.md      "^## \\[${v_re}\\]"
(( fail == 0 )) || exit 1
echo "Version strings are consistent."

bash tests/run.sh

./build_deb.sh >/dev/null
rm -rf -- dist
mkdir dist
mv -- "encryptor_${version}-1_all.deb" dist/

# tar.umask=022: directories are archived as 755 (git's default is 775).
git -c tar.umask=0022 archive --format=tar.gz --prefix="encryptor-${version}/" -o "dist/encryptor-${version}.tar.gz" HEAD

# The tarball must be installable on its own.
work="$(mktemp -d)"
trap 'rm -rf -- "$work"' EXIT
tar -xzf "dist/encryptor-${version}.tar.gz" -C "$work"
"$work/encryptor-${version}/install.sh" --prefix "$work/prefix" >/dev/null
[[ "$("$work/prefix/bin/encryptor" version)" == "Encryptor v${version}" ]] || { echo "tarball install check failed" >&2; exit 1; }

( cd dist && sha256sum "encryptor_${version}-1_all.deb" "encryptor-${version}.tar.gz" > SHA256SUMS && sha256sum -c SHA256SUMS >/dev/null )

echo
echo "Release artifacts in dist/:"
ls -l dist
echo
cat dist/SHA256SUMS
