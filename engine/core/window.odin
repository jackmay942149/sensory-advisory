package core

import "base:runtime"
import "core:log"
import "core:os"
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
p_req_validation_layers :: []cstring{"VK_LAYER_KHRONOS_validation"}
@(private)
p_avail_validation_layers: [dynamic]string
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
@(private)
p_device_extensions :: []cstring{"VK_KHR_swapchain"}
@(private)
p_avail_extensions: [dynamic]string
@(private)
p_swapchain: vk.SwapchainKHR
@(private)
p_swapchain_images: [dynamic]vk.Image
@(private)
p_swapchain_image_format: vk.Format
@(private)
p_swapchain_extent: vk.Extent2D
@(private)
p_swapchain_image_views: [dynamic]vk.ImageView

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

	delete(p_avail_extensions)
	delete(p_avail_validation_layers)

	for image in p_swapchain_image_views {
		vk.DestroyImageView(p_logical_device, image, nil)
	}
	delete(p_swapchain_image_views)
	vk.DestroySwapchainKHR(p_logical_device, p_swapchain, nil)
	delete(p_swapchain_images)

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
	create_swapchain()
	create_image_views()
	create_graphics_pipeline()
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
		enabledLayerCount       = u32(len(p_req_validation_layers)),
		ppEnabledLayerNames     = raw_data(p_req_validation_layers),
	}

	populate_debug_messenger_create_info(&debug_info)
	info.pNext = &debug_info

	assert(vk.CreateInstance(&info, nil, &p_instance) == .SUCCESS)
}

@(private = "file")
check_validation_layer :: proc() -> bool {
	layer_count: u32
	vk.EnumerateInstanceLayerProperties(&layer_count, nil)
	available_layers := make([]vk.LayerProperties, layer_count)
	defer delete(available_layers)
	vk.EnumerateInstanceLayerProperties(&layer_count, raw_data(available_layers))

	for &layer in available_layers {
		l := strings.trim_null(string(layer.layerName[:]))
		append(&p_avail_validation_layers, l)
		log.info("Available validation layer:", l)
	}

	for layer in p_req_validation_layers {
		if slice.contains(p_avail_validation_layers[:], string(layer)) {
			continue
		}
		log.error(layer, "validation layer required and not found")
		return false
	}
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
	assert(vk.CreateDebugUtilsMessengerEXT(p_instance, &info, nil, &p_debug_messenger) == .SUCCESS)
}

@(private = "file")
populate_debug_messenger_create_info :: proc(info: ^vk.DebugUtilsMessengerCreateInfoEXT) {
	info.sType = .DEBUG_UTILS_MESSENGER_CREATE_INFO_EXT
	info.messageSeverity = {.VERBOSE, .WARNING, .ERROR}
	info.messageType = {.GENERAL, .VALIDATION, .PERFORMANCE}
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
	log.info(count, "devices found")

	// Check for first suitable device
	devices := make([]vk.PhysicalDevice, count, context.allocator)
	defer delete(devices)
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
	graphics_family:     Maybe(u32),
	presentation_family: Maybe(u32),
}

@(private = "file")
is_queue_complete :: proc(using queue: QueueFamilyIndicies) -> bool {
	_, has_graphics := graphics_family.?
	_, has_presentation := presentation_family.?
	return has_graphics && has_presentation
}

@(private = "file")
is_device_suitable :: proc(device: vk.PhysicalDevice) -> bool {
	properties: vk.PhysicalDeviceProperties
	vk.GetPhysicalDeviceProperties(device, &properties)
	features: vk.PhysicalDeviceFeatures
	vk.GetPhysicalDeviceFeatures(device, &features)

	indicies := find_queue_families(device)
	extensions_supported := check_device_extension_support(device)

	swapchain_adequate: bool
	if extensions_supported {
		swapchain_support := query_swapchain_support(device)
		swapchain_adequate = len(swapchain_support.formats) > 0
		swapchain_adequate = swapchain_adequate && len(swapchain_support.present_modes) > 0
		delete(swapchain_support.formats) // TODO: make query swapchain support take an allocator and write a delete function for it
		delete(swapchain_support.present_modes)
	}
	return is_queue_complete(indicies) && extensions_supported && swapchain_adequate
	// TODO: Device Selection To Favour Dedicated GPU
	// TODO: Look into multi viewport rendering feature
}

@(private = "file")
find_queue_families :: proc(device: vk.PhysicalDevice) -> (indicies: QueueFamilyIndicies) {
	count: u32
	vk.GetPhysicalDeviceQueueFamilyProperties(device, &count, nil)
	families := make([]vk.QueueFamilyProperties, count, context.allocator)
	defer delete(families)
	vk.GetPhysicalDeviceQueueFamilyProperties(device, &count, raw_data(families))

	for q, i in families {
		if vk.QueueFlag.GRAPHICS in q.queueFlags {
			presentation_support: b32
			vk.GetPhysicalDeviceSurfaceSupportKHR(device, u32(i), p_surface, &presentation_support)
			if (presentation_support == false) {
				continue
			}
			indicies.presentation_family = u32(i)
			indicies.graphics_family = u32(i)
			log.info("Found suitable device", device, "with queue flags:", q.queueFlags)
			break
		}
	}
	return indicies
}

@(private = "file")
create_logical_device :: proc() {
	indicies := find_queue_families(p_physical_device) //  Todo: Possible optimisation here to cache this from an earlier call
	priority: f32 = 1.0

	q_info_graphics := vk.DeviceQueueCreateInfo {
		sType            = .DEVICE_QUEUE_CREATE_INFO,
		queueFamilyIndex = indicies.graphics_family.?,
		queueCount       = 1,
		pQueuePriorities = &priority,
	}

	q_info_presentation := vk.DeviceQueueCreateInfo {
		sType            = .DEVICE_QUEUE_CREATE_INFO,
		queueFamilyIndex = indicies.presentation_family.?,
		queueCount       = 1,
		pQueuePriorities = &priority,
	}

	q_set: map[u32]vk.DeviceQueueCreateInfo
	defer delete(q_set)
	map_insert(&q_set, indicies.graphics_family.?, q_info_graphics)
	map_insert(&q_set, indicies.presentation_family.?, q_info_presentation)

	q_info: [dynamic]vk.DeviceQueueCreateInfo
	defer delete(q_info)
	for _, v in q_set {
		append(&q_info, v)
	}

	features: vk.PhysicalDeviceFeatures
	info := vk.DeviceCreateInfo {
		sType                   = .DEVICE_CREATE_INFO,
		pQueueCreateInfos       = raw_data(q_info[:]),
		queueCreateInfoCount    = u32(len(q_info)),
		pEnabledFeatures        = &features,
		enabledExtensionCount   = u32(len(p_device_extensions)),
		ppEnabledExtensionNames = raw_data(p_device_extensions),
	}

	if (vk.CreateDevice(p_physical_device, &info, nil, &p_logical_device) != .SUCCESS) {
		log.fatal("Failed to create logical device")
	}

	// Get handle to graphics queue
	vk.GetDeviceQueue(p_logical_device, indicies.graphics_family.?, 0, &p_graphics_queue)

	// Get handle to presentation queue
	vk.GetDeviceQueue(p_logical_device, indicies.presentation_family.?, 0, &p_presentation_queue)
	assert(p_presentation_queue != nil)
}

@(private = "file")
create_surface :: proc() {
	if glfw.CreateWindowSurface(p_instance, p_window, nil, &p_surface) != .SUCCESS {
		log.fatal("Failed to create window surface")
	}
}

@(private = "file")
check_device_extension_support :: proc(device: vk.PhysicalDevice) -> bool {
	// TODO: Have the available extensions cached and logged, also do this for check_validation_layer
	count: u32
	vk.EnumerateDeviceExtensionProperties(device, nil, &count, nil)

	available_ext := make([]vk.ExtensionProperties, count, context.allocator)
	defer delete(available_ext)
	vk.EnumerateDeviceExtensionProperties(device, nil, &count, raw_data(available_ext))

	for &ext in available_ext {
		e := strings.trim_null(string(ext.extensionName[:]))
		append(&p_avail_extensions, e)
		log.info(e)
	}

	for ext in p_device_extensions {
		if slice.contains(p_avail_extensions[:], string(ext)) {
			continue
		}
		log.error(ext, "extension required and not found")
		return false
	}
	return true
}

@(private = "file")
SwapchainSupportDetails :: struct {
	capabilities:  vk.SurfaceCapabilitiesKHR,
	formats:       [dynamic]vk.SurfaceFormatKHR,
	present_modes: [dynamic]vk.PresentModeKHR,
}

@(private = "file")
query_swapchain_support :: proc(device: vk.PhysicalDevice) -> (details: SwapchainSupportDetails) {
	vk.GetPhysicalDeviceSurfaceCapabilitiesKHR(device, p_surface, &details.capabilities)

	count: u32
	vk.GetPhysicalDeviceSurfaceFormatsKHR(device, p_surface, &count, nil)
	if count != 0 {
		details.formats = make([dynamic]vk.SurfaceFormatKHR, count, context.allocator)
		vk.GetPhysicalDeviceSurfaceFormatsKHR(device, p_surface, &count, raw_data(details.formats))
	}

	count = 0
	vk.GetPhysicalDeviceSurfacePresentModesKHR(device, p_surface, &count, nil)
	if count != 0 {
		details.present_modes = make([dynamic]vk.PresentModeKHR, count, context.allocator)
		vk.GetPhysicalDeviceSurfacePresentModesKHR(
			device,
			p_surface,
			&count,
			raw_data(details.present_modes),
		)
	}
	return details
}

@(private = "file")
choose_swapchain_surface_format :: proc(
	avail_formats: ^[dynamic]vk.SurfaceFormatKHR,
) -> vk.SurfaceFormatKHR {
	for format in avail_formats {
		if format.format == .R8G8B8A8_SRGB && format.colorSpace == .SRGB_NONLINEAR {
			return format
		}
	}
	assert(len(avail_formats) > 0)
	log.warn("Swapchain surface format is non standard")
	return avail_formats[0] // TODO: improve non standard format picking
}

@(private = "file")
choose_swapchain_present_mode :: proc(
	avail_modes: ^[dynamic]vk.PresentModeKHR,
) -> vk.PresentModeKHR {
	for mode in avail_modes {
		if mode == .MAILBOX {
			return mode
		}
	}
	return .FIFO
}

@(private = "file")
choose_swapchain_extent :: proc(using capabilities: ^vk.SurfaceCapabilitiesKHR) -> vk.Extent2D {
	if (currentExtent.width != max(u32)) {
		return currentExtent // Trick to query if window manager allows us to change extent
	}

	width, height := glfw.GetFramebufferSize(p_window)
	actual_extent := vk.Extent2D {
		clamp(u32(width), minImageExtent.width, maxImageExtent.width),
		clamp(u32(height), maxImageExtent.height, maxImageExtent.height),
	}
	return actual_extent
}

@(private = "file")
create_swapchain :: proc() {
	swapchain_support := query_swapchain_support(p_physical_device) // TODO: check if logical device should be passed here
	surface_format := choose_swapchain_surface_format(&swapchain_support.formats)
	present_mode := choose_swapchain_present_mode(&swapchain_support.present_modes)
	extent := choose_swapchain_extent(&swapchain_support.capabilities)
	defer {
		delete(swapchain_support.formats)
		delete(swapchain_support.present_modes)
	}

	image_count := swapchain_support.capabilities.minImageCount + 1
	max_image_count := swapchain_support.capabilities.maxImageCount
	if max_image_count > 0 && image_count > max_image_count {
		image_count = max_image_count
	}

	info := vk.SwapchainCreateInfoKHR {
		sType            = .SWAPCHAIN_CREATE_INFO_KHR,
		surface          = p_surface,
		minImageCount    = image_count,
		imageFormat      = surface_format.format,
		imageColorSpace  = surface_format.colorSpace,
		imageExtent      = extent,
		imageArrayLayers = 1,
		imageUsage       = {.COLOR_ATTACHMENT},
		preTransform     = swapchain_support.capabilities.currentTransform,
		compositeAlpha   = {.OPAQUE},
		presentMode      = present_mode,
		clipped          = true,
		oldSwapchain     = 0,
	}

	indicies := find_queue_families(p_physical_device)
	queue_family_indicies := [?]u32{indicies.graphics_family.?, indicies.presentation_family.?}

	if (indicies.graphics_family != indicies.presentation_family) {
		info.imageSharingMode = .CONCURRENT
		info.queueFamilyIndexCount = 2
		info.pQueueFamilyIndices = raw_data(queue_family_indicies[:])
	} else {
		info.imageSharingMode = .EXCLUSIVE
		info.pQueueFamilyIndices = nil
	}

	if vk.CreateSwapchainKHR(p_logical_device, &info, nil, &p_swapchain) != .SUCCESS {
		log.fatal("Failed to create swapchain")
	}

	vk.GetSwapchainImagesKHR(p_logical_device, p_swapchain, &image_count, nil)
	p_swapchain_images = make([dynamic]vk.Image, image_count, context.allocator)
	vk.GetSwapchainImagesKHR(
		p_logical_device,
		p_swapchain,
		&image_count,
		raw_data(p_swapchain_images),
	)
	p_swapchain_image_format = surface_format.format
	p_swapchain_extent = extent
}

@(private = "file")
create_image_views :: proc() {
	p_swapchain_image_views = make([dynamic]vk.ImageView, len(p_swapchain_images))
	for image, i in p_swapchain_image_views {
		info := vk.ImageViewCreateInfo {
			sType    = .IMAGE_VIEW_CREATE_INFO,
			image    = p_swapchain_images[i],
			viewType = vk.ImageViewType.D2,
			format   = p_swapchain_image_format,
		}
		info.components.r = .IDENTITY
		info.components.g = .IDENTITY
		info.components.b = .IDENTITY
		info.components.a = .IDENTITY
		info.subresourceRange.aspectMask = {.COLOR}
		info.subresourceRange.baseMipLevel = 0
		info.subresourceRange.levelCount = 1
		info.subresourceRange.baseArrayLayer = 0
		info.subresourceRange.layerCount = 1

		if vk.CreateImageView(p_logical_device, &info, nil, &p_swapchain_image_views[i]) !=
		   .SUCCESS {
			log.fatal("Failed to create image views")
		}
	}
}

@(private = "file")
create_graphics_pipeline :: proc() {
	vertex_shader_data, err := os.read_entire_file_from_filename_or_err(
		"./assets/vert.spv",
		context.allocator,
	)
	if err != nil {
		log.fatal("Could not find vertex shader")
	}

	fragment_shader_data: []u8
	fragment_shader_data, err = os.read_entire_file_from_filename_or_err(
		"./assets/frag.spv",
		context.allocator,
	)
	if err != nil {
		log.fatal("Could not find fragment shader")
	}

	vertex_shader_module := create_shader_module(vertex_shader_data)
	fragment_shader_module := create_shader_module(fragment_shader_data)
	defer {
		vk.DestroyShaderModule(p_logical_device, fragment_shader_module, nil)
		vk.DestroyShaderModule(p_logical_device, vertex_shader_module, nil)
		delete(vertex_shader_data)
		delete(fragment_shader_data)
	}

	vertex_info := vk.PipelineShaderStageCreateInfo {
		sType  = .PIPELINE_SHADER_STAGE_CREATE_INFO,
		stage  = {.VERTEX},
		module = vertex_shader_module,
		pName  = "main",
	}
	fragment_info := vk.PipelineShaderStageCreateInfo {
		sType  = .PIPELINE_SHADER_STAGE_CREATE_INFO,
		stage  = {.FRAGMENT},
		module = fragment_shader_module,
		pName  = "main",
	}
	shader_stages := [?]vk.PipelineShaderStageCreateInfo{vertex_info, fragment_info}

	dynamic_states := [?]vk.DynamicState{.VIEWPORT, .SCISSOR}
	dynamic_state_info := vk.PipelineDynamicStateCreateInfo {
		sType             = .PIPELINE_DYNAMIC_STATE_CREATE_INFO,
		dynamicStateCount = u32(len(dynamic_states)),
		pDynamicStates    = raw_data(dynamic_states[:]),
	}

	vertex_input_info := vk.PipelineVertexInputStateCreateInfo {
		sType                           = .PIPELINE_VERTEX_INPUT_STATE_CREATE_INFO,
		vertexBindingDescriptionCount   = 0,
		pVertexBindingDescriptions      = nil,
		vertexAttributeDescriptionCount = 0,
		pVertexAttributeDescriptions    = nil,
	}
}

@(private = "file")
create_shader_module :: proc(data: []u8) -> vk.ShaderModule {
	info := vk.ShaderModuleCreateInfo {
		sType    = .SHADER_MODULE_CREATE_INFO,
		codeSize = len(data),
		pCode    = cast(^u32)raw_data(data),
	}
	shader: vk.ShaderModule
	vk.CreateShaderModule(p_logical_device, &info, nil, &shader)
	return shader
}

