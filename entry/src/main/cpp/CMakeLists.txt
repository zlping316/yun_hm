cmake_minimum_required(VERSION 3.5)
project(mp4remux)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

add_library(mp4remux SHARED napi_init.cpp)

target_link_libraries(mp4remux PUBLIC
    libace_napi.z.so
    libnative_media_core.so
    libnative_media_codecbase.so
    libnative_media_avsource.so
    libnative_media_avdemuxer.so
    libnative_media_avmuxer.so
)
