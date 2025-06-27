package main

import "base:runtime"
import "core:log"
import "core:mem"
import "engine/core"
import "engine/extensions/input"

main :: proc() {
	context.logger = core.init_logger("./log.txt")
	tracker: ^mem.Tracking_Allocator
	tracker, context.allocator = core.init_tracker()
	glfw_ctx := core.init_window(1920 / 2, 1080 / 2, "Vulkan")
	input.init(glfw_ctx.window)

	key := input.Key {
		code     = .M,
		modifier = {.Alt},
		action   = .Release,
	}
	input.bind_key(key, core.maximise_window)
	defer {
		core.destroy_window()
		input.destroy()
		core.destroy_tracker(tracker) // Do Last
	}

	for !core.window_should_close() {

	}
}

set_title_a :: proc() {
	core.set_window_title("A")
}
set_title_b :: proc() {
	core.set_window_title("B")
}

