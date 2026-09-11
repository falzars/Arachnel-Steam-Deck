#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
QT_VERSION="6.11.1"
QT_ROOT="$HOME/.local/share/Arachnel/qt"
QT_DIR="$QT_ROOT/$QT_VERSION/gcc_64"
VENV_DIR="$ROOT_DIR/.aqt-venv"
BUILD_DIR="$ROOT_DIR/build-qt611"
LAUNCHER="$BUILD_DIR/run-arachnel-qt611.sh"

echo "=== Arachnel Steam Deck / Qt $QT_VERSION ==="

if [[ ! -f "$QT_DIR/lib/cmake/Qt6/Qt6Config.cmake" ]]; then
    echo "[1/4] Installation locale de Qt $QT_VERSION..."
    python3 -m venv "$VENV_DIR"
    "$VENV_DIR/bin/python" -m pip install --upgrade pip wheel
    # Qt 6.11 needs the current aqtinstall code path; this matches the release workflow approach.
    "$VENV_DIR/bin/python" -m pip install --upgrade "git+https://github.com/miurahr/aqtinstall.git"
    "$VENV_DIR/bin/aqt" install-qt \
        linux desktop "$QT_VERSION" linux_gcc_64 \
        -O "$QT_ROOT" \
        -m qtmultimedia qtshadertools
else
    echo "[1/4] Qt $QT_VERSION déjà installé."
fi

if [[ ! -f "$QT_DIR/lib/cmake/Qt6/Qt6Config.cmake" ]]; then
    echo "ERREUR: Qt $QT_VERSION n'a pas été installé correctement dans:"
    echo "  $QT_DIR"
    exit 1
fi

if command -v git-lfs >/dev/null 2>&1; then
    echo "[2/4] Synchronisation Git LFS..."
    git -C "$ROOT_DIR" lfs pull
else
    echo "[2/4] git-lfs absent, étape ignorée."
fi

echo "[3/4] Compilation avec le même Qt que la release officielle..."
cmake -S "$ROOT_DIR" -B "$BUILD_DIR" \
    -G Ninja \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_CXX_COMPILER=g++ \
    -DCMAKE_PREFIX_PATH="$QT_DIR" \
    -DQt6_DIR="$QT_DIR/lib/cmake/Qt6" \
    -DARACHNEL_FAST_BUILD=ON

cmake --build "$BUILD_DIR" --target arachnel_app -j"$(nproc)"

echo "[4/4] Création du lanceur Qt $QT_VERSION..."
cat > "$LAUNCHER" <<EOF
#!/usr/bin/env bash
set -e
QT_DIR="$QT_DIR"
BUILD_DIR="$BUILD_DIR"
export LD_LIBRARY_PATH="\$QT_DIR/lib\${LD_LIBRARY_PATH:+:\$LD_LIBRARY_PATH}"
export QT_PLUGIN_PATH="\$QT_DIR/plugins\${QT_PLUGIN_PATH:+:\$QT_PLUGIN_PATH}"
export QML_IMPORT_PATH="\$QT_DIR/qml\${QML_IMPORT_PATH:+:\$QML_IMPORT_PATH}"
export QML2_IMPORT_PATH="\$QT_DIR/qml\${QML2_IMPORT_PATH:+:\$QML2_IMPORT_PATH}"
exec "\$BUILD_DIR/arachnel_app" "\$@"
EOF
chmod +x "$LAUNCHER"

echo
echo "OK: Arachnel est maintenant compilé et lancé avec Qt $QT_VERSION."
echo "Lanceur permanent:"
echo "  $LAUNCHER"
echo
exec "$LAUNCHER"
