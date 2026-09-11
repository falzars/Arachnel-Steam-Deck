#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ARACHNEL="$ROOT/build/arachnel_app"

if [[ ! -x "$ARACHNEL" ]]; then
  echo "Arachnel binary not found or not executable: $ARACHNEL" >&2
  echo "Build it first with: cmake --build build --target arachnel_app -j\"$(nproc)\"" >&2
  exit 1
fi

# The source build is compiled against the SteamOS Qt toolchain. Do not inject
# Qt libraries/plugins from the extracted official AppImage: mixing those two
# Qt installations can corrupt the QML engine and crash at shutdown/runtime.
unset LD_LIBRARY_PATH
unset QT_PLUGIN_PATH
unset QT_QPA_PLATFORM_PLUGIN_PATH
unset QML2_IMPORT_PATH
unset QML_IMPORT_PATH
unset QT_QML_MATERIAL_IMPORT_PATH

exec "$ARACHNEL" "$@"
