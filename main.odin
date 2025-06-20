package main

import "base:runtime"
import "core:log"
import "core:mem"
import "engine/core"

main :: proc() {
	context.logger = core.init_logger("./log.txt")
	tracker: ^mem.Tracking_Allocator
	tracker, context.allocator = core.init_tracker()

	core.init_window(1920 / 2, 1080 / 2, "Vulkan")
	for !core.window_should_close() {

	}
	core.close_window()

	core.destroy_tracker(tracker)
}

