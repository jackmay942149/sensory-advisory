package main

import "base:runtime"
import "core:log"
import "core:mem"
import "engine/core"
import "engine/extensions/input"

main :: proc() {
	context.logger = core.init_logger("./log.txt", .Jack, .All)
	tracker: ^mem.Tracking_Allocator
	tracker, context.allocator = core.init_tracker()
	glfw_ctx := core.init_window(1920 / 2, 1080 / 2, "Vulkan")
	input.init(glfw_ctx.window)

	key1 := input.Key{.M, {.Ctrl}, .Press}
	key2 := input.Key{.T, {.Alt}, .Press}
	input.bind_key(key1, core.maximise_window)
	input.bind_toggle(key2, set_title_a, set_title_b)
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

