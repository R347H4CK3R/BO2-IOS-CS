#!/bin/bash
set -euo pipefail
SOURCE="${1:?usage: $0 /path/to/extracted/GameData [output-dir]}"
OUT="${2:-PrivateConversion}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
mkdir -p "$OUT"
python3 "$ROOT/Tools/PS3AssetConverter/private_asset_import.py" --source "$SOURCE" --output "$OUT" --extract-ipak
python3 "$ROOT/Tools/PS3AssetConverter/media_convert.py" --source "$SOURCE" --output "$OUT"
echo "Generated runtime data: $OUT/GeneratedGameData"
echo "Copy that GeneratedGameData directory into the private build workspace before packaging."
