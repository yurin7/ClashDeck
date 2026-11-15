cmake_minimum_required(VERSION 3.22.1)

project(clashdeckspawn C)

add_library(clashdeckspawn SHARED spawn.c)

# log 库在这个 shim 里没用上，但保留链接方便以后加 native 日志。
find_library(log-lib log)
target_link_libraries(clashdeckspawn ${log-lib})
