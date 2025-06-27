package core

import "base:runtime"
import "core:log"
import "core:os"
import "core:slice"
import "core:strings"
import "vendor:glfw"
import vk "vendor:vulkan"

GLFW_Context :: struct {
	window: glfw.WindowHandle,
}

@(private)
odin_ctx: runtime.Context
@(private)
glfw_ctx: GLFW_Context

init_window :: proc(width: i32, height: i32, title: string) -> GLFW_Context {
	odin_ctx = context
	assert(glfw_ctx.window == nil)
	glfw.Init()
	glfw.WindowHint(glfw.CLIENT_API, glfw.NO_API)
	glfw.WindowHint(glfw.RESIZABLE, glfw.TRUE)
	glfw_title := strings.clone_to_cstring(title, context.allocator)
	defer delete(glfw_title)
	glfw_ctx.window = glfw.CreateWindow(width, height, glfw_title, nil, nil)
	assert(glfw_ctx.window != nil)
	init_vulkan()
	log.info("Initialised window")
	return glfw_ctx
}

window_should_close :: proc() -> bool {
	glfw.PollEvents()
	draw_frame()

	if glfw.GetKey(glfw_ctx.window, glfw.KEY_ESCAPE) == glfw.PRESS {
		return true
	}
	vk_assert(vk.DeviceWaitIdle(vk_ctx.logical_device), "Failed to wait for synchronisation")
	return bool(glfw.WindowShouldClose(glfw_ctx.window))
}

destroy_window :: proc() { 	// TODO: have a destroy vulkan function
	assert(glfw_ctx.window != nil)
	assert(vk_ctx.instance != nil)
	vk_assert(vk.DeviceWaitIdle(vk_ctx.logical_device), "Failed to wait for synchronisation")
	delete(vk_ctx.avail_extensions)
	delete(vk_ctx.avail_validation_layers)
	cleanup_swapchain(true)
	vk.DestroySemaphore(vk_ctx.logical_device, vk_ctx.image_avail_semaphore, nil)
	vk.DestroySemaphore(vk_ctx.logical_device, vk_ctx.render_finished_semaphore, nil)
	vk.DestroyFence(vk_ctx.logical_device, vk_ctx.in_flight_fence, nil)
	vk.DestroyCommandPool(vk_ctx.logical_device, vk_ctx.command_pool, nil)
	vk.DestroyPipeline(vk_ctx.logical_device, vk_ctx.graphics_pipeline, nil)
	vk.DestroyPipelineLayout(vk_ctx.logical_device, vk_ctx.pipeline_layout, nil)
	vk.DestroyRenderPass(vk_ctx.logical_device, vk_ctx.render_pass, nil)
	delete(vk_ctx.swapchain_images)
	vk.DestroySurfaceKHR(vk_ctx.instance, vk_ctx.surface, nil)
	vk.DestroyDevice(vk_ctx.logical_device, nil)
	vk.DestroyDebugUtilsMessengerEXT(vk_ctx.instance, vk_ctx.debug_messenger, nil)
	vk.DestroyInstance(vk_ctx.instance, nil)
	vk_ctx.instance = nil
	glfw.DestroyWindow(glfw_ctx.window)
	glfw.Terminate()
	glfw_ctx.window = nil
	log.info("Closed window")
}

maximise_window :: proc() {
	glfw.MaximizeWindow(glfw_ctx.window)
}

borderless_window :: proc() {
	monitor := glfw.GetPrimaryMonitor()
	borderless := glfw.GetVideoMode(monitor)
	glfw.SetWindowMonitor(
		glfw_ctx.window,
		monitor,
		0,
		0,
		borderless.width,
		borderless.height,
		borderless.refresh_rate,
	)
}

set_window_title :: proc(title: string) {
	c := strings.clone_to_cstring(title, context.allocator)
	delete(c)
	glfw.SetWindowTitle(glfw_ctx.window, c)
}

