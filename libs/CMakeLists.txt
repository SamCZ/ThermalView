add_subdirectory(libusb)

set(BUILD_EXAMPLE OFF)
add_subdirectory(libuvc)

#------------------------------
# GLFW
# Desktop Window Library
#------------------------------
if(NOT TARGET glfw AND NOT ANDROID)
	set(GLFW_INSTALL OFF)
	set(GLFW_BUILD_EXAMPLES OFF)
	set(GLFW_BUILD_TESTS OFF)
	set(GLFW_BUILD_DOCS OFF)
	#set(GLFW_USE_HYBRID_HPG ON)
	if (WIN32)
		set(GLFW_BUILD_WIN32 ON)
	endif ()
	if (APPLE)
		set(GLFW_BUILD_COCOA ON)
	endif ()
	add_subdirectory(glfw)
endif()

add_subdirectory(glm)