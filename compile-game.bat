@echo off
odin build . -define:RELEASE=false -define:VALIDATION_LAYERS=false
"./sensory-advisory.exe"
