cmake_minimum_required(VERSION 3.21)
project(pond-interface LANGUAGES CXX)
find_package(Qt6 6.11 REQUIRED COMPONENTS Qml)
find_package(KF6NetworkManagerQt REQUIRED)
qt_standard_project_setup(REQUIRES 6.7)
qt_add_qml_module(pond_wifi_status
    URI Pond.WifiStatus
    VERSION 1.0
    OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/Pond/WifiStatus"
    SOURCES lockscreen/frontend/system/NetworkStatus.h
)
target_include_directories(pond_wifi_status PRIVATE lockscreen/frontend/system)
target_link_libraries(pond_wifi_status PRIVATE KF6::NetworkManagerQt)
set_target_properties(pond_wifi_statusplugin PROPERTIES INSTALL_RPATH "$ORIGIN")

add_subdirectory(localization)

add_subdirectory(screenshot/native)
install(TARGETS pond_wifi_status pond_wifi_statusplugin
    LIBRARY DESTINATION lib/qt6/qml/Pond/WifiStatus)
install(FILES "${CMAKE_BINARY_DIR}/Pond/WifiStatus/qmldir"
    "${CMAKE_BINARY_DIR}/Pond/WifiStatus/pond_wifi_status.qmltypes"
    DESTINATION lib/qt6/qml/Pond/WifiStatus)
install(DIRECTORY shell lockscreen DESTINATION share/pond-interface
    PATTERN "__pycache__" EXCLUDE)
install(DIRECTORY screenshot/ DESTINATION lib/qt6/qml/Pond/Screenshot
    PATTERN "native" EXCLUDE PATTERN "__pycache__" EXCLUDE)
install(DIRECTORY wallpaper/ DESTINATION lib/qt6/qml/Pond/Wallpaper
    PATTERN "daylight" EXCLUDE)
install(DIRECTORY wallpaper/daylight/ DESTINATION lib/qt6/qml/Pond/Daylight)
