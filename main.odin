package main

import "base:runtime"
import "core:fmt"
import "engine/core"

g_ctx: runtime.Context

main :: proc() {
	g_ctx = context
	core.init_logger(&g_ctx, "./log.txt")
	context = g_ctx
	core.init_window(1920 / 2, 1080 / 2, "Vulkan")

	for !core.window_should_close() {

	}

	core.close_window()
	core.close_logger()
}

