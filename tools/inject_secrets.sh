#!/bin/sh
# Build phase: copies FDC_API_KEY from the (git-ignored) .env file into the app bundle as Secrets.plist.
# A missing .env or empty key is fine; the app falls back to the shared DEMO_KEY.
ENV_FILE="$SRCROOT/.env"
KEY=""
if [ -f "$ENV_FILE" ]; then
  KEY=$(grep -E '^[[:space:]]*FDC_API_KEY=' "$ENV_FILE" | head -1 | cut -d= -f2- | tr -d '"'"'"' \r')
fi
OUT="$TARGET_BUILD_DIR/$UNLOCALIZED_RESOURCES_FOLDER_PATH/Secrets.plist"
cat > "$OUT" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict><key>FDC_API_KEY</key><string>$KEY</string></dict></plist>
PLIST
