#!/bin/zsh
# Adalmon: libimobiledevice ve bağımlılıklarını Homebrew'dan Vendor/libimobiledevice içine kopyalar,
# kurulum adlarını @rpath'e çevirir. Bir kez (ya da sürüm yükseltirken) çalıştırılır; imzalamayı Xcode yapar
# (project.yml: framework bağımlılıkları, embed + codeSign).
#   brew install libimobiledevice && tools/vendor-libimobiledevice.sh
set -euo pipefail
setopt null_glob
export HOMEBREW_NO_AUTO_UPDATE=1
prefix=${HOMEBREW_PREFIX:-/opt/homebrew}
dest="${0:A:h:h}/Vendor/libimobiledevice"
mkdir -p "$dest/licenses"
libs=(
  "$prefix/opt/libimobiledevice/lib/libimobiledevice-1.0.6.dylib"
  "$prefix/opt/libimobiledevice-glue/lib/libimobiledevice-glue-1.0.0.dylib"
  "$prefix/opt/libplist/lib/libplist-2.0.12.dylib"
  "$prefix/opt/libusbmuxd/lib/libusbmuxd-2.0.7.dylib"
  "$prefix/opt/openssl@4/lib/libssl.4.dylib"
  "$prefix/opt/openssl@4/lib/libcrypto.4.dylib"
)
for src in $libs; do
  [[ -f $src ]] || { echo "bulunamadı: $src" >&2; exit 1 }
  cp -f "$src" "$dest/${src:t}"
  chmod u+w "$dest/${src:t}"
done
for f in "$dest"/*.dylib; do
  name=${f:t}
  install_name_tool -id "@rpath/$name" "$f" 2>/dev/null
  # Homebrew yollarını @rpath'e çevir (yalnızca paketlenen kitaplıklar).
  for dep in $(otool -L "$f" | tail -n +2 | awk '{print $1}' | grep -E '^/opt/homebrew|^/usr/local/(opt|Cellar)' || true); do
    install_name_tool -change "$dep" "@rpath/${dep:t}" "$f"
  done
  # Aynı dizindeki kardeşleri bulsun (dlopen ile mutlak yoldan yüklenirken de çalışır).
  install_name_tool -add_rpath "@loader_path" "$f" 2>/dev/null || true
done
# Lisanslar (her paketin COPYING* / LICENSE* dosyaları)
for d in libimobiledevice libimobiledevice-glue libplist libusbmuxd openssl@4; do
  cellar=$(readlink -f "$prefix/opt/$d" 2>/dev/null || true)
  found=0
  for file in "$cellar"/COPYING* "$cellar"/LICENSE*; do
    [[ -f $file ]] && { cp -f "$file" "$dest/licenses/${d}-${file:t}"; found=1 }
  done
  [[ $found == 1 ]] || echo "uyarı: $d lisans dosyası bulunamadı" >&2
done
echo "== otool -L (yalnızca Homebrew/mutlak yol kalmamalı)"
bad=0
for f in "$dest"/*.dylib; do
  if otool -L "$f" | tail -n +2 | grep -E '/opt/homebrew|/usr/local' >/dev/null; then echo "HATA: $f"; bad=1; fi
done
[[ $bad == 0 ]] && echo "tamam" || exit 1
