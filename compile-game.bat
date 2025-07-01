@echo off
odin build . -define:RELEASE=true
"./sensory-advisory.exe"
