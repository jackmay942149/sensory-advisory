package core

import "base:runtime"
import "vendor:glfw"
import vk "vendor:vulkan"

Vulkan_Info :: struct {
	odin_ctx:        runtime.Context,
	instance:        vk.Instance,
	debug_messenger: vk.DebugUtilsMessengerEXT,
	physical_device: vk.PhysicalDevice,
	surface:         vk.SurfaceKHR,
	logical_device:  vk.Device,
	queues:          []vk.Queue,
}

App_Info :: struct {
	name:              cstring,
	version:           u32,
	engine:            Engine_Info,
	req_global_ext:    []cstring,
	req_global_layers: []cstring,
	req_device_ext:    []cstring,
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
	topic_info(.Graphics, "Rating", len(devices), "physical devices")
	for d in devices {
		count, queues := query_queue_info(d)
		defer delete(queues)
		topic_info(.Graphics, "Device", d, "has", count, "queues with properties", queues)
	}
	assert(len(devices) > 0)
	best = devices[0]
	return best
}

@(private = "file", require_results)
query_queue_info :: proc(
	device: vk.PhysicalDevice,
) -> (
	count: u32,
	properties: []vk.QueueFamilyProperties,
) {
	vk.GetPhysicalDeviceQueueFamilyProperties(device, &count, nil)
	properties = make([]vk.QueueFamilyProperties, count)
	vk.GetPhysicalDeviceQueueFamilyProperties(device, &count, raw_data(properties))
	return count, properties
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
create_logical_device_2 :: proc(
	physical_device: vk.PhysicalDevice,
	app_info: App_Info,
) -> (
	device: vk.Device,
) {
	queue_count, queues := query_queue_info(physical_device)
	queue_create_infos := make([]vk.DeviceQueueCreateInfo, queue_count)
	priority: f32 = 1
	for _, i in queues {
		info := vk.DeviceQueueCreateInfo {
			sType            = .DEVICE_QUEUE_CREATE_INFO,
			queueFamilyIndex = u32(i),
			queueCount       = 1,
			pQueuePriorities = &priority,
		}
		queue_create_infos[i] = info
	}
	info := vk.DeviceCreateInfo {
		sType                   = .DEVICE_CREATE_INFO,
		queueCreateInfoCount    = queue_count,
		pQueueCreateInfos       = raw_data(queue_create_infos),
		enabledExtensionCount   = u32(len(app_info.req_device_ext)),
		ppEnabledExtensionNames = raw_data(app_info.req_device_ext),
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

get_queue_handles :: proc(
	physical_device: vk.PhysicalDevice,
	device: vk.Device,
) -> (
	queue_handles: []vk.Queue,
) {
	count, queues := query_queue_info(physical_device)
	queue_handles = make([]vk.Queue, count)
	for i in 0 ..< count {
		vk.GetDeviceQueue(device, i, 0, &queue_handles[i])
	}
	return queue_handles
}

