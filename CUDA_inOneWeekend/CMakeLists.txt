cmake_minimum_required(VERSION 3.16)

# Project name and version
project(RTIOW VERSION 1.0.0 LANGUAGES CXX)

# Set C++ standard
set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)

# Add compiler-specific options
if(MSVC)
    # Visual Studio specific options
    add_compile_options(/W4)
    # Enable parallel compilation
    add_compile_options(/MP)
else()
    # GCC/Clang options
    add_compile_options(-Wall -Wextra -Wpedantic)
endif()

# Add the executable
add_executable(rtiow src/main.cc)

# Set output directory for executables
set_target_properties(rtiow PROPERTIES
    RUNTIME_OUTPUT_DIRECTORY ${CMAKE_BINARY_DIR}/bin
)

# Optional: Set up different build types
if(NOT CMAKE_BUILD_TYPE)
    set(CMAKE_BUILD_TYPE Release)
endif()

# Add custom target to run the program and generate image
add_custom_target(run_rtiow
    COMMAND rtiow > image.ppm
    DEPENDS rtiow
    WORKING_DIRECTORY ${CMAKE_BINARY_DIR}/bin
    COMMENT "Running RTIOW and generating image.ppm"
)

# Print some information
message(STATUS "Project: ${PROJECT_NAME}")
message(STATUS "Version: ${PROJECT_VERSION}")
message(STATUS "C++ Standard: ${CMAKE_CXX_STANDARD}")
message(STATUS "Build Type: ${CMAKE_BUILD_TYPE}")