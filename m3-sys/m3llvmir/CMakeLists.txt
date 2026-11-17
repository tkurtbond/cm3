# Needed to compile bootstrap (cm3 imports m3llvmir).
add_library(m3llvmir STATIC)
target_link_libraries(m3llvmir PUBLIC m3middle)
include(sources.lst)
target_sources(m3llvmir PRIVATE ${cm3_SOURCES})
