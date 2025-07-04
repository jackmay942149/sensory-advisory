package core

import "base:runtime"
import "vendor:glfw"
import vk "vendor:vulkan"

Vulkan_Info :: struct {
	odin_ctx:        runtime.Context,
	instance:        vk.Instance,
	physical_device: vk.PhysicalDevice,
	surface:         vk.SurfaceKHR,
	logical_device:  vk.Device,
}

App_Info :: struct {
	name:              cstring,
	version:           u32,
	engine:            Engine_Info,
	req_global_ext:    []cstring,
	req_global_layers: []cstring,
}

Engine_Info :: struct {
	name:        cstring,
	version:     u32,
	api_version: u32,
}

@(private, require_results)
create_instance :: proc(app: App_Info) -> (instance: vk.Instance) {
	// Load fp's
	vk.load_proc_addresses_global(rawptr(glfw.GetInstanceProcAddress))
	assert(vk.CreateInstance != nil)
	// Get api version
	version: u32
	vk_result := vk.EnumerateInstanceVersion(&version)
	vk_fatal(vk_result, "Failed to get vulkan version this is likely due to vulkan version 1.0")
	topic_info(.Graphics, "I think this is api version:", version) // TODO: test what this is
	// Create app info
	app_info := vk.ApplicationInfo {
		sType              = .APPLICATION_INFO,
		pApplicationName   = app.name,
		applicationVersion = app.version,
		pEngineName        = app.engine.name,
		engineVersion      = app.engine.version,
		apiVersion         = app.engine.api_version,
	}
	// Create instance TODO: Add debug report callback here as debug messenger is not setup yet
	info := vk.InstanceCreateInfo {
		sType                   = .INSTANCE_CREATE_INFO,
		pApplicationInfo        = &app_info,
		enabledExtensionCount   = u32(len(app.req_global_ext)),
		enabledLayerCount       = u32(len(app.req_global_layers)),
		ppEnabledExtensionNames = raw_data(app.req_global_ext[:]),
		ppEnabledLayerNames     = raw_data(app.req_global_layers[:]),
	}
	vk_result = vk.CreateInstance(&info, nil, &instance)
	topic_info(.Graphics, "Instance has address: ", instance, vk_result)
	vk_fatal(vk_result, "Failed to create instance")
	return instance
}

@(private = "file")
vk_fatal :: proc(result: vk.Result, message: string) {
	if result == .SUCCESS do return
	topic_fatal(.Graphics, result, message)
}

@(private, require_results)
setup_validation :: proc(
	instance: vk.Instance,
	severity: vk.DebugUtilsMessageSeverityFlagsEXT,
	type: vk.DebugUtilsMessageTypeFlagsEXT,
) -> (
	debug_messenger: vk.DebugUtilsMessengerEXT,
) {
	info := vk.DebugUtilsMessengerCreateInfoEXT {
		sType           = .DEBUG_UTILS_MESSENGER_CREATE_INFO_EXT,
		messageSeverity = severity,
		messageType     = type,
		pfnUserCallback = debug_callback,
		pUserData       = nil,
	}
	result := vk.CreateDebugUtilsMessengerEXT(instance, &info, nil, &debug_messenger)
	return debug_messenger
}

@(private = "file")
debug_callback :: proc "system" (
	severity: vk.DebugUtilsMessageSeverityFlagsEXT,
	type: vk.DebugUtilsMessageTypeFlagsEXT,
	callback_data: ^vk.DebugUtilsMessengerCallbackDataEXT,
	user_data: rawptr,
) -> b32 {
	context = odin_ctx
	switch {
	case .VERBOSE in severity:
		topic_info(.Vulkan_Validation, callback_data.pMessage)
	case .INFO in severity:
		topic_info(.Vulkan_Validation, callback_data.pMessage)
	case .WARNING in severity:
		topic_info(.Vulkan_Validation, callback_data.pMessage)
	case .ERROR in severity:
		topic_error(.Vulkan_Validation, callback_data.pMessage)
	}
	return false
}

@(private, require_results)
get_physical_device :: proc(instance: vk.Instance) -> (physical_device: vk.PhysicalDevice) {
	device_count: u32
	result := vk.EnumeratePhysicalDevices(instance, &device_count, nil)
	vk_fatal(result, "Failed to enumerate physical devices")
	assert(device_count > 0)
	devices := make([]vk.PhysicalDevice, device_count)
	defer delete(devices)
	result = vk.EnumeratePhysicalDevices(instance, &device_count, raw_data(devices))
	physical_device = rate_physical_devices(&devices)
	return physical_device
}

@(private = "file")
rate_physical_devices :: proc(devices: ^[]vk.PhysicalDevice) -> (best: vk.PhysicalDevice) {
	// TODO: Make a rating system
	assert(len(devices) > 0)
	best = devices[0]
	return best
}

@(private, require_results)
create_surface :: proc(
	instance: vk.Instance,
	window: glfw.WindowHandle,
) -> (
	surface: vk.SurfaceKHR,
) {
	result := glfw.CreateWindowSurface(instance, window, nil, &surface)
	vk_fatal(result, "Failed to create window surface")
	return surface
}

@(private, require_results)
create_logical_device :: proc(physical_device: vk.PhysicalDevice) -> (device: vk.Device) {
	info := vk.DeviceCreateInfo {
		sType                   = .DEVICE_CREATE_INFO,
		queueCreateInfoCount    = 0, // TODO:
		pQueueCreateInfos       = nil, // TODO:
		enabledLayerCount       = 0, // TODO:
		ppEnabledLayerNames     = nil, // TODO:
		enabledExtensionCount   = 0, // TODO:
		ppEnabledExtensionNames = nil, // TODO:		
	}
	result := vk.CreateDevice(physical_device, &info, nil, &device)
	// TODO: this switch can be simplified by querying extensions and layers instead of just throwing errors
	#partial switch result {
	case .ERROR_EXTENSION_NOT_PRESENT:
		topic_fatal(
			.Graphics,
			result,
			"Failed creating logical device where an extension was not present",
		)
	case .ERROR_LAYER_NOT_PRESENT:
		topic_fatal(.Graphics, result, "Failed to create logical device because layer not present")
	case .ERROR_TOO_MANY_OBJECTS:
		topic_fatal(
			.Graphics,
			"failed to create logical device because to many logical devices exist",
		)
	case:
		vk_fatal(result, "Failed to create logical device")
	}
	return device
}

