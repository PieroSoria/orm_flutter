#!/bin/sh
set -eu
engine_source="$PROJECT_DIR/../prisma/engines"
engine_destination="$TARGET_BUILD_DIR/$EXECUTABLE_FOLDER_PATH"
mkdir -p "$engine_destination"
for engine in query-engine schema-engine; do
  cp "$engine_source/$engine" "$engine_destination/prisma-$engine"
  chmod 755 "$engine_destination/prisma-$engine"
  /usr/bin/codesign --force --sign "${EXPANDED_CODE_SIGN_IDENTITY:--}" --entitlements "$PROJECT_DIR/Flutter/PrismaEngine.entitlements" "$engine_destination/prisma-$engine"
done
