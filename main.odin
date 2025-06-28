package main

import "base:runtime"
import "core:log"
import "core:mem"
import "engine/core"
import "engine/extensions/input"

input_ctx_1: input.Mapping_Context
input_ctx_2: input.Mapping_Context

main :: proc() {
	context.logger = core.init_logger("./log.txt", .Jack, .All)
	tracker: ^mem.Tracking_Allocator
	tracker, context.allocator = core.init_tracker()
	glfw_ctx := core.init_window(1920 / 2, 1080 / 2, "Vulkan")
	input.init(glfw_ctx.window)
	input_ctx_1 = input.init_mapping_ctx(glfw_ctx.window)
	input_ctx_2 = input.init_mapping_ctx(glfw_ctx.window)
	input.bind_mapping_ctx(&input_ctx_1)

	key1 := input.Key{.T, {}, .Press}
	input.bind_toggle(&input_ctx_1, key1, set_title_a, set_title_b)
	key2 := input.Key{.C, {}, .Press}
	input.bind_toggle(key2, set_ctx_2, set_ctx_1)
	input.bind_toggle(&input_ctx_2, key1, set_title_c, set_title_d)
	defer {
		core.destroy_window()
		input.destroy(&input_ctx_1, &input_ctx_2)
		core.destroy_tracker(tracker) // Do Last
	}

	key := input.Key{.P, {}, .Press}
	for !core.window_should_close() {
		if input.is_key_down(key) {
			core.user_error(.Jack, "P is pressed")
		}
	}
}

set_ctx_1 :: proc() {
	input.bind_mapping_ctx(&input_ctx_1)
}
set_ctx_2 :: proc() {
	input.bind_mapping_ctx(&input_ctx_2)
}
set_title_a :: proc() {
	core.set_window_title("Context 1: A")
}
set_title_b :: proc() {
	core.set_window_title("Context 1: B")
}
set_title_c :: proc() {
	core.set_window_title("Context 2: C")
}
set_title_d :: proc() {
	core.set_window_title("Context 2: D")
}

