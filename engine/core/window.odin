package core

import "base:runtime"
import "core:log"
import "core:slice"
import "core:strings"
import "vendor:glfw"
import vk "vendor:vulkan"

// Package Variables
@(private)
p_ctx: runtime.Context
@(private)
p_window: glfw.WindowHandle
@(private)
p_instance: vk.Instance
@(private)
p_debug_messenger: vk.DebugUtilsMessengerEXT
@(private)
p_validation_layers :: []cstring{"VK_LAYER_KHRONOS_validation"}
@(private)
p_physical_device: vk.PhysicalDevice
@(private)
p_logical_device: vk.Device
@(private)
p_graphics_queue: vk.Queue
@(private)
p_surface: vk.SurfaceKHR
@(private)
p_presentation_queue: vk.Queue

init_window :: proc(width: i32, height: i32, title: cstring) {
	p_ctx = context
	assert(p_window == nil)
	glfw.Init()
	glfw.WindowHint(glfw.CLIENT_API, glfw.NO_API)
	glfw.WindowHint(glfw.RESIZABLE, glfw.FALSE)
	p_window = glfw.CreateWindow(width, height, title, nil, nil)
	assert(p_window != nil)
	init_vulkan()
	log.info("Initialised window")
}

window_should_close :: proc() -> bool {
	glfw.PollEvents()

	if glfw.GetKey(p_window, glfw.KEY_ESCAPE) == glfw.PRESS {
		return true
	}
	return bool(glfw.WindowShouldClose(p_window))
}

close_window :: proc() {
	assert(p_window != nil)
	assert(p_instance != nil)
	assert(p_logical_device != nil)

	vk.DestroySurfaceKHR(p_instance, p_surface, nil)

	vk.DestroyDevice(p_logical_device, nil)
	p_logical_device = nil

	vk.DestroyDebugUtilsMessengerEXT(p_instance, p_debug_messenger, nil)

	vk.DestroyInstance(p_instance, nil)
	p_instance = nil

	glfw.DestroyWindow(p_window)
	glfw.Terminate()
	p_window = nil
	log.info("Closed window")
}

@(private = "file")
init_vulkan :: proc() {
	create_instance()
	vk.load_proc_addresses_instance(p_instance)
	setup_debug_messenger()
	create_surface()
	pick_physical_device()
	create_logical_device()
}

@(private = "file")
create_instance :: proc() {
	// Load function pointers check odin example for this
	vk.load_proc_addresses_global(rawptr(glfw.GetInstanceProcAddress))
	assert(vk.CreateInstance != nil)

	check_validation_layer()

	app_info := vk.ApplicationInfo {
		sType              = .APPLICATION_INFO,
		pApplicationName   = "Hello Triangle",
		applicationVersion = vk.MAKE_VERSION(1, 0, 0),
		pEngineName        = "No Engine",
		engineVersion      = vk.MAKE_VERSION(1, 0, 0),
		apiVersion         = vk.API_VERSION_1_0,
	}

	extensions: [dynamic]cstring
	defer delete(extensions)
	get_required_extensions(&extensions)
	log.info("Vulkan extensions required:", extensions)

	debug_info: vk.DebugUtilsMessengerCreateInfoEXT
	info := vk.InstanceCreateInfo {
		sType                   = .INSTANCE_CREATE_INFO,
		pApplicationInfo        = &app_info,
		enabledExtensionCount   = u32(len(extensions)),
		ppEnabledExtensionNames = raw_data(extensions),
		enabledLayerCount       = u32(len(p_validation_layers)),
		ppEnabledLayerNames     = raw_data(p_validation_layers),
	}

	populate_debug_messenger_create_info(&debug_info)
	info.pNext = &debug_info

	assert(vk.CreateInstance(&info, nil, &p_instance) == vk.Result.SUCCESS)
}

@(private = "file")
check_validation_layer :: proc() -> bool {
	layer_count: u32
	vk.EnumerateInstanceLayerProperties(&layer_count, nil)
	available_layers := make([]vk.LayerProperties, layer_count) // TODO: allocator/delete
	vk.EnumerateInstanceLayerProperties(&layer_count, raw_data(available_layers))
	for layer_name in p_validation_layers {
		layer_found: bool
		for &layer_properties in available_layers { 	// Add & to make [256]byte addressable
			available_layer := strings.clone_to_cstring(
				strings.trim_null(transmute(string)(layer_properties.layerName[:])),
				context.allocator,
			)
			if layer_name == available_layer {
				layer_found = true
			}
			delete(available_layer)
		}
		assert(layer_found == true)
	}
	delete(available_layers)
	return true
}

@(private = "file")
get_required_extensions :: proc(extensions: ^[dynamic]cstring) {
	required_extensions := glfw.GetRequiredInstanceExtensions()
	cstr: cstring = vk.EXT_DEBUG_UTILS_EXTENSION_NAME
	append(extensions, ..required_extensions[:])
	append(extensions, cstr)
}

@(private = "file")
debug_callback :: proc "system" (
	severity: vk.DebugUtilsMessageSeverityFlagsEXT,
	type: vk.DebugUtilsMessageTypeFlagsEXT,
	callback_data: ^vk.DebugUtilsMessengerCallbackDataEXT,
	user_data: rawptr,
) -> b32 {
	context = p_ctx
	switch {
	case .VERBOSE in severity:
		log.debug("Vulkan Validation Layer Message:", callback_data.pMessage)
	case .INFO in severity:
		log.info("Vulkan Validation Layer Message:", callback_data.pMessage)
	case .WARNING in severity:
		log.warn("Vulkan Validation Layer Message:", callback_data.pMessage)
	case .ERROR in severity:
		log.error("Vulkan Validation Layer Message:", callback_data.pMessage)
	}
	return false
}

@(private = "file")
setup_debug_messenger :: proc() {
	info: vk.DebugUtilsMessengerCreateInfoEXT
	populate_debug_messenger_create_info(&info)
	assert(
		vk.CreateDebugUtilsMessengerEXT(p_instance, &info, nil, &p_debug_messenger) ==
		vk.Result.SUCCESS,
	)
}

@(private = "file")
populate_debug_messenger_create_info :: proc(info: ^vk.DebugUtilsMessengerCreateInfoEXT) {
	info.sType = .DEBUG_UTILS_MESSENGER_CREATE_INFO_EXT
	info.messageSeverity = vk.DebugUtilsMessageSeverityFlagsEXT{.VERBOSE, .WARNING, .ERROR}
	info.messageType = vk.DebugUtilsMessageTypeFlagsEXT{.GENERAL, .VALIDATION, .PERFORMANCE}
	info.pfnUserCallback = debug_callback
	info.pUserData = nil
}

@(private = "file")
pick_physical_device :: proc() {
	// Get all physical devices
	count: u32
	vk.EnumeratePhysicalDevices(p_instance, &count, nil)
	if count == 0 {
		log.fatal("No vulkan physical devices found")
	}

	// Check for first suitable device
	devices := make([]vk.PhysicalDevice, count, context.temp_allocator)
	defer free_all(context.temp_allocator)
	vk.EnumeratePhysicalDevices(p_instance, &count, raw_data(devices))
	for d in devices {
		if is_device_suitable(d) {
			log.info("Using device:", d)
			p_physical_device = d
			break
		}
	}
}

QueueFamilyIndicies :: struct {
	has_graphics:        bool,
	graphics_family:     u32,
	has_presentation:    bool,
	presentation_family: u32,
}

@(private = "file")
is_queue_complete :: proc(using queue: QueueFamilyIndicies) -> bool {
	return has_graphics && has_presentation
}

@(private = "file")
is_device_suitable :: proc(device: vk.PhysicalDevice) -> bool {
	properties: vk.PhysicalDeviceProperties
	vk.GetPhysicalDeviceProperties(device, &properties)
	features: vk.PhysicalDeviceFeatures
	vk.GetPhysicalDeviceFeatures(device, &features)

	indicies := find_queue_families(device)

	return is_queue_complete(indicies)
	// TODO: Device Selection To Favour Dedicated GPU
	// TODO: Look into multi viewport rendering feature
}

@(private = "file")
find_queue_families :: proc(device: vk.PhysicalDevice) -> (indicies: QueueFamilyIndicies) {
	count: u32
	vk.GetPhysicalDeviceQueueFamilyProperties(device, &count, nil)
	families := make([]vk.QueueFamilyProperties, count, context.temp_allocator)
	defer free_all(context.allocator)
	vk.GetPhysicalDeviceQueueFamilyProperties(device, &count, raw_data(families))

	for q, i in families {
		if vk.QueueFlag.GRAPHICS in q.queueFlags {
			presentation_support: b32
			vk.GetPhysicalDeviceSurfaceSupportKHR(device, u32(i), p_surface, &presentation_support)
			if (presentation_support == false) {
				continue
			}
			indicies.presentation_family = u32(i)
			indicies.has_presentation = true
			indicies.graphics_family = u32(i)
			indicies.has_graphics = true
			log.info("Found suitable device", device, "with queue flags:", q.queueFlags)
			break
		}
	}
	return indicies
}

@(private = "file")
create_logical_device :: proc() {
	indicies := find_queue_families(p_physical_device)
	priority: f32 = 1.0

	q_info_graphics := vk.DeviceQueueCreateInfo {
		sType            = vk.StructureType.DEVICE_QUEUE_CREATE_INFO,
		queueFamilyIndex = indicies.graphics_family,
		queueCount       = 1,
		pQueuePriorities = &priority,
	}

	q_info_presentation := vk.DeviceQueueCreateInfo {
		sType            = vk.StructureType.DEVICE_QUEUE_CREATE_INFO,
		queueFamilyIndex = indicies.presentation_family,
		queueCount       = 1,
		pQueuePriorities = &priority,
	}

	q_set: map[u32]vk.DeviceQueueCreateInfo
	defer delete(q_set)
	map_insert(&q_set, indicies.graphics_family, q_info_graphics)
	map_insert(&q_set, indicies.presentation_family, q_info_presentation)

	q_info: [dynamic]vk.DeviceQueueCreateInfo
	defer delete(q_info)
	for _, v in q_set {
		append(&q_info, v)
	}

	features: vk.PhysicalDeviceFeatures
	info := vk.DeviceCreateInfo {
		sType                 = vk.StructureType.DEVICE_CREATE_INFO,
		pQueueCreateInfos     = raw_data(q_info[:]),
		queueCreateInfoCount  = u32(len(q_info)),
		pEnabledFeatures      = &features,
		enabledExtensionCount = 0,
	}

	if (vk.CreateDevice(p_physical_device, &info, nil, &p_logical_device) != vk.Result.SUCCESS) {
		log.fatal("Failed to create logical device")
	}

	// Get handle to graphics queue
	vk.GetDeviceQueue(p_logical_device, indicies.graphics_family, 0, &p_graphics_queue)

	// Get handle to presentation queue
	vk.GetDeviceQueue(p_logical_device, indicies.presentation_family, 0, &p_presentation_queue)
	assert(p_presentation_queue != nil)
}

@(private = "file")
create_surface :: proc() {
	if glfw.CreateWindowSurface(p_instance, p_window, nil, &p_surface) != vk.Result.SUCCESS {
		log.fatal("Failed to create window surface")
	}
}

