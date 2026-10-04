cmake_minimum_required(VERSION 3.14)
project(orm_flutter LANGUAGES CXX)

if(DEFINED FLUTTER_TARGET_PLATFORM AND NOT FLUTTER_TARGET_PLATFORM STREQUAL "windows-x64")
  message(FATAL_ERROR "orm_flutter includes Windows x64 engines only. Unsupported target: ${FLUTTER_TARGET_PLATFORM}")
endif()
set(ENGINE_DIR "${CMAKE_CURRENT_SOURCE_DIR}/../desktop/engines/windows")
set(orm_flutter_bundled_libraries
  "${ENGINE_DIR}/prisma-query-engine.exe"
  "${ENGINE_DIR}/prisma-schema-engine.exe"
  "${CMAKE_CURRENT_SOURCE_DIR}/../desktop/PRISMA_LICENSE"
  PARENT_SCOPE
)
foreach(ENGINE query-engine schema-engine)
  if(NOT EXISTS "${ENGINE_DIR}/prisma-${ENGINE}.exe")
    message(FATAL_ERROR "orm_flutter package is missing its bundled ${ENGINE} executable.")
  endif()
endforeach()
