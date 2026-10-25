cmake_minimum_required(VERSION 3.21)
project(pic-config VERSION 0.1.0 LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_AUTOMOC ON)
set(CMAKE_AUTORCC ON)

find_package(Qt6 REQUIRED COMPONENTS Widgets)

# Every data/devices/*.cfgdata is embedded. To support a new PIC, drop its
# cfgdata file in that folder and re-run cmake; no code changes.
file(GLOB DEVICE_FILES CONFIGURE_DEPENDS "${CMAKE_CURRENT_SOURCE_DIR}/data/devices/*.cfgdata")
set(QRC "${CMAKE_CURRENT_BINARY_DIR}/devices.qrc")
set(QRC_BODY "<RCC><qresource prefix=\"/devices\">\n")
foreach(f ${DEVICE_FILES})
    get_filename_component(n "${f}" NAME)
    string(APPEND QRC_BODY "<file alias=\"${n}\">${f}</file>\n")
endforeach()
string(APPEND QRC_BODY "</qresource></RCC>\n")
file(GENERATE OUTPUT "${QRC}" CONTENT "${QRC_BODY}")
set_property(SOURCE "${QRC}" PROPERTY GENERATED ON)
set_property(SOURCE "${QRC}" PROPERTY SKIP_AUTORCC OFF)

qt_add_executable(pic-config
    src/main.cpp
    src/DeviceDef.cpp
    src/DeviceDef.h
    src/OutputFormatter.cpp
    src/OutputFormatter.h
    src/MainWindow.cpp
    src/MainWindow.h
    "${QRC}"
)
target_link_libraries(pic-config PRIVATE Qt6::Widgets)
