package main

import "base:runtime"
import "core:log"
import "core:mem"
import "engine/core"
import "engine/extensions/input"
import "vendor:glfw"

main :: proc() {
	when core.RELEASE == false {
		context.logger = core.init_logger("./log.txt", .Jack, .All)
		tracker: ^mem.Tracking_Allocator
		tracker, context.allocator = core.init_tracker()
	}
	glfw_ctx := core.init_window(1920 / 2, 1080 / 2, "Vulkan")
	input.init(glfw_ctx.window)
	input.bind_key(input.Key{.Gamepad_A, {}, .Press}, core.close_window)
	input.bind_key(input.Key{.Escape, {}, .Press}, core.close_window)
	defer {
		core.delete_all_updates()
		core.destroy_window()
		input.destroy()
		defer when core.RELEASE == false {
			core.destroy_tracker(tracker)
		}
	}

	for !core.window_should_close() {
		core.update_callbacks()
	}
}

