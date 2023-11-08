cmake_minimum_required(VERSION 3.26)
project(TermalApp)

set(CMAKE_POLICY_DEFAULT_CMP0077 NEW)
set(CMAKE_CXX_STANDARD 20)
enable_language(OBJC)
enable_language(OBJCXX)

add_subdirectory(libs)

file(GLOB_RECURSE SOURCE_FILES src/*.h src/*.hpp src/*.cpp src/*.mm)
add_executable(TermalApp ${SOURCE_FILES})
target_link_libraries(TermalApp PUBLIC glfw glm usb-1.0 uvc_static)

target_link_libraries(TermalApp PUBLIC
				"-framework Metal"
				"-framework MetalKit"
				"-framework AppKit"
				"-framework Foundation"
				"-framework QuartzCore"
)