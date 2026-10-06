#!/usr/bin/env bash
# Quits a running copy, packages the app, and opens it.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
pkill -x SkillsPack || true
"$ROOT/Scripts/package_app.sh"
open "$ROOT/build/SkillsPack.app"
