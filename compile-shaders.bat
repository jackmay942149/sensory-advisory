@echo off
glslc.exe ./assets/default.vert -o ./assets/vert.spv
glslc.exe ./assets/default.frag -o ./assets/frag.spv
pause
