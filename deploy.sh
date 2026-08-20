#!/bin/bash
set -euo pipefail

APP_NAME="ClaudeUsageDashboard"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DIST_APP="$ROOT_DIR/dist/$APP_NAME.app"
INSTALLED_APP="/Applications/$APP_NAME.app"

echo "==> Build + assemblage..."
"$ROOT_DIR/build_app.sh"

echo "==> Fermeture de l'instance en cours..."
pkill -f "$APP_NAME.app/Contents/MacOS/$APP_NAME" 2>/dev/null || true
pkill -f "$ROOT_DIR/.build/debug/$APP_NAME" 2>/dev/null || true
sleep 1

echo "==> Remplacement de la version installée..."
rm -rf "$INSTALLED_APP"
cp -R "$DIST_APP" "$INSTALLED_APP"

echo "==> Relance..."
open -a "$INSTALLED_APP"

echo "==> Terminé : $INSTALLED_APP mise à jour et relancée."
