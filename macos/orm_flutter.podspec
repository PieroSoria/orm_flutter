Pod::Spec.new do |s|
  s.name = 'orm_flutter'
  s.version = '0.5.1'
  s.summary = 'Prisma query and migration engines for Flutter.'
  s.description = s.summary
  s.homepage = 'https://github.com/PieroSoria/orm_flutter'
  s.license = { :file => '../LICENSE' }
  s.author = { 'orm_flutter contributors' => 'https://github.com/PieroSoria/orm_flutter' }
  s.source = { :path => '.' }
  s.source_files = 'orm_flutter/Sources/orm_flutter/**/*.swift'
  s.resource_bundles = { 'orm_flutter_engines' => ['orm_flutter/Sources/orm_flutter/Engines/prisma-*', 'orm_flutter/Sources/orm_flutter/Engines/PRISMA_LICENSE'] }
  s.dependency 'FlutterMacOS'
  s.platform = :osx, '12.0'
  s.swift_version = '5.0'
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES' }
  s.script_phase = {
    :name => 'Sign Prisma engines',
    :execution_position => :after_compile,
    :script => <<-SCRIPT
set -eu
bundle="${BUILT_PRODUCTS_DIR}/orm_flutter_engines.bundle/Contents/Resources"
if [ ! -d "$bundle" ]; then bundle="${BUILT_PRODUCTS_DIR}/orm_flutter_engines.bundle"; fi
for engine in query-engine schema-engine; do
  chmod 755 "$bundle/prisma-$engine"
  /usr/bin/codesign --force --sign "${EXPANDED_CODE_SIGN_IDENTITY:--}" --entitlements "${PODS_TARGET_SRCROOT}/Engine.entitlements" "$bundle/prisma-$engine"
done
    SCRIPT
  }
end
