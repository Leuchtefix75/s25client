SET(Boost_USE_STATIC_LIBS TRUE)

#Check for ccache
find_program(CCACHE_FOUND ccache)
MARK_AS_ADVANCED(CCACHE_FOUND)
if(CCACHE_FOUND)
	MESSAGE(STATUS "Using ccache to speed up builds")
	set_property(GLOBAL PROPERTY RULE_LAUNCH_COMPILE ccache)
	set_property(GLOBAL PROPERTY RULE_LAUNCH_LINK ccache)
endif(CCACHE_FOUND)

# set compiler flags
IF(RTTR_ENABLE_OPTIMIZATIONS)
  IF(("${PLATFORM_ARCH}" STREQUAL "x86_64") OR ("${PLATFORM_ARCH}" STREQUAL "i386"))
	FORCE_ADD_FLAGS(CMAKE_C_FLAGS -ffast-math -mmmx -msse -mfpmath=sse -ggdb)
	FORCE_ADD_FLAGS(CMAKE_CXX_FLAGS -ffast-math -mmmx -msse -mfpmath=sse -ggdb)
  ELSEIF("${PLATFORM_ARCH}" STREQUAL "universal")
        # 4 pears are one apple!
  ELSE()
        # simply suggest that all other stuff is ARM
        FORCE_ADD_FLAGS(CMAKE_C_FLAGS   -O3 -march=armv7-a -mfpu=neon -mfloat-abi=hard -DRTTR_HW_CURSOR)
        FORCE_ADD_FLAGS(CMAKE_CXX_FLAGS -O3 -march=armv7-a -mfpu=neon -mfloat-abi=hard -DRTTR_HW_CURSOR)
  ENDIF()	
ENDIF(RTTR_ENABLE_OPTIMIZATIONS)
