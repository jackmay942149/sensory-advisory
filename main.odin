package main

import "core"
import "core:fmt"

main :: proc() {
	core.initWindow(1920 / 2, 1080 / 2, "Vulkan")
	for !core.windowShouldClose() {

	}
	core.closeWindow()
}

