#!/usr/bin/env bash
set -euo pipefail

root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
bundle="$root/build/linux/x64/release/bundle"

[[ $(uname -m) == x86_64 ]] || { echo '目前仅支持 x86_64。' >&2; exit 1; }
for command in python makepkg zstd desktop-file-validate; do
  command -v "$command" >/dev/null || { echo "缺少打包工具：$command" >&2; exit 1; }
done
[[ -x $bundle/nai_launcher && -x $bundle/nai_launcher_mcp ]] || {
  echo '未找到完整的主程序和 MCP 可执行文件。' >&2
  exit 1
}

mkdir -p "$root/tool/.tmp" "$root/dist"
recipe="$(mktemp -d "$root/tool/.tmp/arch-package.XXXXXX")"
cp -- "$root/packaging/arch/"* "$recipe/"
cp -- "$root/LICENSE" "$root/THIRD_PARTY_NOTICES.md" "$recipe/"
cp -- "$root/assets/icons/Icon.png" "$recipe/nai-launcher.png"
version="$(python -c 'import pathlib,re,sys; print(re.search(r"^version:\s*(\d+\.\d+\.\d+)", pathlib.Path(sys.argv[1]).read_text(), re.M).group(1))' "$root/pubspec.yaml")"
glibc_version="$(getconf GNU_LIBC_VERSION | cut -d ' ' -f2)"
payload="nai-launcher-$version-linux-x86_64.tar.zst"
tar --zstd -cf "$recipe/$payload" -C "$bundle" . -C "$root" licenses/fonts

cd -- "$recipe"
python - "$version" "$glibc_version" <<'PY'
from pathlib import Path
import hashlib
import sys

version, glibc_version = sys.argv[1:]
sources = [
    f'nai-launcher-{version}-linux-x86_64.tar.zst', 'LICENSE',
    'THIRD_PARTY_NOTICES.md', 'nai-launcher.desktop',
    'nai-launcher', 'nai-launcher-mcp', 'nai-launcher.png',
]
hashes = '\n  '.join("'" + hashlib.sha256(Path(name).read_bytes()).hexdigest() + "'" for name in sources)
template = Path('PKGBUILD.in').read_text()
Path('PKGBUILD').write_text(template.replace('@VERSION@', version)
    .replace('@GLIBC@', glibc_version).replace('@SHA256SUMS@', hashes))
PY
bash -n PKGBUILD
desktop-file-validate nai-launcher.desktop
makepkg --verifysource
PKGDEST="$root/dist" makepkg --force
makepkg --printsrcinfo > .SRCINFO
package_file="$(PKGDEST="$root/dist" makepkg --packagelist)"
(cd -- "$root/dist" && sha256sum -- "$(basename -- "$package_file")" > SHA256SUMS)
