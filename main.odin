package main

import "base:runtime"
import "core:log"
import "core:mem"
import "engine/core"

g_ctx: runtime.Context
g_tracker: mem.Tracking_Allocator

main :: proc() {
	g_ctx = context
	core.init_logger(&g_ctx, "./log.txt")
	context = g_ctx
	g_tracker = core.init_tracker(&g_ctx)
	context.allocator = mem.tracking_allocator(&g_tracker)

	core.init_window(1920 / 2, 1080 / 2, "Vulkan")
	for !core.window_should_close() {

	}
	core.close_window()

	core.destroy_tracker(&g_tracker)
}

