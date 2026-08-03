# audiopus_sys invokes CMake without ANDROID_ABI. Select it from Cargo's target
# before delegating to the NDK toolchain, which otherwise defaults to armeabi-v7a.
if("$ENV{TARGET}" MATCHES "^aarch64-")
  set(ANDROID_ABI arm64-v8a)
elseif("$ENV{TARGET}" MATCHES "^armv7-")
  set(ANDROID_ABI armeabi-v7a)
elseif("$ENV{TARGET}" MATCHES "^x86_64-")
  set(ANDROID_ABI x86_64)
elseif("$ENV{TARGET}" MATCHES "^i686-")
  set(ANDROID_ABI x86)
else()
  message(FATAL_ERROR "Unsupported Android Rust target: $ENV{TARGET}")
endif()

include("$ENV{CARGOKIT_NDK_TOOLCHAIN_FILE}")
