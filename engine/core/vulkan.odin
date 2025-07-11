package core

import "core:log"
import "core:math"
import "core:math/linalg"
import "core:mem"
import "core:os"
import "core:slice"
import "core:strings"
import "core:time"
import "vendor:glfw"
import vk "vendor:vulkan"

Vulkan_Context :: struct {
	instance:                  vk.Instance,
	debug_messenger:           vk.DebugUtilsMessengerEXT,
	avail_validation_layers:   [dynamic]string,
	physical_device:           vk.PhysicalDevice,
	logical_device:            vk.Device,
	graphics_queue:            vk.Queue,
	surface:                   vk.SurfaceKHR,
	presentation_queue:        vk.Queue,
	avail_extensions:          [dynamic]string,
	swapchain:                 vk.SwapchainKHR, // Swapchain
	swapchain_images:          [dynamic]vk.Image,
	swapchain_image_format:    vk.Format,
	swapchain_extent:          vk.Extent2D,
	swapchain_image_views:     [dynamic]vk.ImageView,
	render_pass:               vk.RenderPass, // Renderpass
	descriptor_set_layout:     vk.DescriptorSetLayout,
	pipeline_layout:           vk.PipelineLayout,
	graphics_pipeline:         vk.Pipeline,
	swapchain_framebuffers:    [dynamic]vk.Framebuffer,
	command_pool:              vk.CommandPool,
	vertex_buffer:             vk.Buffer,
	vertex_buffer_memory:      vk.DeviceMemory,
	index_buffer:              vk.Buffer,
	index_buffer_memory:       vk.DeviceMemory,
	uniform_buffers:           [dynamic]vk.Buffer,
	uniform_buffers_memory:    [dynamic]vk.DeviceMemory,
	uniform_buffers_mapped:    [dynamic]rawptr,
	command_buffer:            vk.CommandBuffer,
	image_avail_semaphore:     vk.Semaphore,
	render_finished_semaphore: vk.Semaphore,
	in_flight_fence:           vk.Fence,
	start_time:                time.Time,
}

Vertex :: struct {
	pos:   [2]f32,
	color: [3]f32,
}

UBO :: struct {
	model: matrix[4, 4]f32,
	view:  matrix[4, 4]f32,
	proj:  matrix[4, 4]f32,
}

//odinfmt:disable
vertices := [?]Vertex {
	{{-0.5, -0.5}, {1, 0, 0}},
	{{ 0.5, -0.5}, {0, 1, 0}},
	{{ 0.5,  0.5}, {0, 0, 1}},
	{{-0.5,  0.5}, {1, 1, 1}},
}

indicies := [?]u32 {
	0, 1, 2,
	2, 3, 0,
}
//odinfmt:enable

@(private)
vk_ctx: Vulkan_Context

when VALIDATION_LAYERS == false {
	@(private)
	p_req_validation_layers :: []cstring{}
} else {
	@(private)
	p_req_validation_layers :: []cstring{"VK_LAYER_KHRONOS_validation"}
}

@(private)
p_device_extensions :: []cstring{"VK_KHR_swapchain"}

engine_info :: Engine_Info {
	name        = "Wreckless",
	version     = vk.API_VERSION_1_0,
	api_version = vk.API_VERSION_1_0,
}

when VALIDATION_LAYERS == true {
	app_info :: App_Info {
		name              = "Sensory Advisory",
		version           = vk.API_VERSION_1_0,
		engine            = engine_info,
		req_global_ext    = {"VK_KHR_surface", "VK_KHR_win32_surface", "VK_EXT_debug_utils"},
		req_global_layers = {},
		req_device_ext    = {"VK_KHR_swapchain"},
	}
} else {
	app_info :: App_Info {
		name              = "Sensory Advisory",
		version           = vk.API_VERSION_1_0,
		engine            = engine_info,
		req_global_ext    = {"VK_KHR_surface", "VK_KHR_win32_surface"},
		req_global_layers = {},
	}
}

vk_info: Vulkan_Info

@(private)
init_vulkan :: proc(window: glfw.WindowHandle) {
	vk_ctx.start_time = time.now() // TODO: Remove
	vk_info.odin_ctx = context
	vk_info.instance = create_instance(app_info)
	vk.load_proc_addresses_instance(vk_info.instance)
	when VALIDATION_LAYERS == true {
		vk_info.debug_messenger = setup_validation(
			vk_info.instance,
			{.VERBOSE, .INFO, .WARNING, .ERROR},
			{.GENERAL, .VALIDATION, .PERFORMANCE},
		)
	}
	vk_info.physical_device = get_physical_device(vk_info.instance)
	vk_info.surface = create_surface(vk_info.instance, window)
	vk_info.logical_device = create_logical_device_2(vk_info.physical_device, app_info)
	vk_info.queues = get_queue_handles(vk_info.physical_device, vk_info.logical_device)
	/*
	create_swapchain()
	create_image_views()
	create_render_pass()
	create_descriptor_set_layout()
	create_graphics_pipeline()
	create_framebuffers()
	create_command_pool()
	create_vertex_buffer()
	create_index_buffer()
	// create_uniform_buffers()
	create_command_buffer()
	create_sync_objects()
	*/
	assert(false)
}

@(private)
check_validation_layer :: proc() -> bool {
	layer_count: u32
	vk.EnumerateInstanceLayerProperties(&layer_count, nil)
	available_layers := make([]vk.LayerProperties, layer_count)
	defer delete(available_layers)
	vk.EnumerateInstanceLayerProperties(&layer_count, raw_data(available_layers))

	for &layer in available_layers {
		l := strings.trim_null(string(layer.layerName[:]))
		append(&vk_ctx.avail_validation_layers, l)
		log.info("Available validation layer:", l)
	}

	for layer in p_req_validation_layers {
		if slice.contains(vk_ctx.avail_validation_layers[:], string(layer)) {
			continue
		}
		log.error(layer, "validation layer required and not found")
		return false
	}
	return true
}

@(private)
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
	context = odin_ctx
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

@(private)
setup_debug_messenger :: proc() {
	info: vk.DebugUtilsMessengerCreateInfoEXT
	populate_debug_messenger_create_info(&info)
	assert(
		vk.CreateDebugUtilsMessengerEXT(vk_ctx.instance, &info, nil, &vk_ctx.debug_messenger) ==
		.SUCCESS,
	)
}

@(private)
populate_debug_messenger_create_info :: proc(info: ^vk.DebugUtilsMessengerCreateInfoEXT) {
	info.sType = .DEBUG_UTILS_MESSENGER_CREATE_INFO_EXT
	info.messageSeverity = {.VERBOSE, .WARNING, .ERROR}
	info.messageType = {.GENERAL, .VALIDATION, .PERFORMANCE}
	info.pfnUserCallback = debug_callback
	info.pUserData = nil
}

@(private)
pick_physical_device :: proc() {
	// Get all physical devices
	count: u32
	vk.EnumeratePhysicalDevices(vk_ctx.instance, &count, nil)
	if count == 0 {
		log.fatal("No vulkan physical devices found")
	}
	log.info(count, "devices found")

	// Check for first suitable device
	devices := make([]vk.PhysicalDevice, count, context.allocator)
	defer delete(devices)
	vk.EnumeratePhysicalDevices(vk_ctx.instance, &count, raw_data(devices))
	for d in devices {
		if is_device_suitable(d) {
			log.info("Using device:", d)
			vk_ctx.physical_device = d
			break
		}
	}
}

QueueFamilyIndicies :: struct {
	graphics_family:     Maybe(u32),
	presentation_family: Maybe(u32),
}

@(private)
is_queue_complete :: proc(using queue: QueueFamilyIndicies) -> bool {
	_, has_graphics := graphics_family.?
	_, has_presentation := presentation_family.?
	return has_graphics && has_presentation
}

@(private)
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

@(private)
find_queue_families :: proc(device: vk.PhysicalDevice) -> (indicies: QueueFamilyIndicies) {
	count: u32
	vk.GetPhysicalDeviceQueueFamilyProperties(device, &count, nil)
	families := make([]vk.QueueFamilyProperties, count, context.allocator)
	defer delete(families)
	vk.GetPhysicalDeviceQueueFamilyProperties(device, &count, raw_data(families))

	for q, i in families {
		if vk.QueueFlag.GRAPHICS in q.queueFlags {
			presentation_support: b32
			vk.GetPhysicalDeviceSurfaceSupportKHR(
				device,
				u32(i),
				vk_ctx.surface,
				&presentation_support,
			)
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

@(private)
create_logical_device :: proc() {
	indicies := find_queue_families(vk_ctx.physical_device) //  Todo: Possible optimisation here to cache this from an earlier call
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

	if (vk.CreateDevice(vk_ctx.physical_device, &info, nil, &vk_ctx.logical_device) != .SUCCESS) {
		log.fatal("Failed to create logical device")
	}

	// Get handle to graphics queue
	vk.GetDeviceQueue(vk_ctx.logical_device, indicies.graphics_family.?, 0, &vk_ctx.graphics_queue)

	// Get handle to presentation queue
	vk.GetDeviceQueue(
		vk_ctx.logical_device,
		indicies.presentation_family.?,
		0,
		&vk_ctx.presentation_queue,
	)
	assert(vk_ctx.presentation_queue != nil)
}

@(private)
check_device_extension_support :: proc(device: vk.PhysicalDevice) -> bool {
	// TODO: Have the available extensions cached and logged, also do this for check_validation_layer
	count: u32
	vk.EnumerateDeviceExtensionProperties(device, nil, &count, nil)

	available_ext := make([]vk.ExtensionProperties, count, context.allocator)
	defer delete(available_ext)
	vk.EnumerateDeviceExtensionProperties(device, nil, &count, raw_data(available_ext))

	for &ext in available_ext {
		e := strings.trim_null(string(ext.extensionName[:]))
		append(&vk_ctx.avail_extensions, e)
		log.info(e)
	}

	for ext in p_device_extensions {
		if slice.contains(vk_ctx.avail_extensions[:], string(ext)) {
			continue
		}
		log.error(ext, "extension required and not found")
		return false
	}
	return true
}

@(private)
SwapchainSupportDetails :: struct {
	capabilities:  vk.SurfaceCapabilitiesKHR,
	formats:       [dynamic]vk.SurfaceFormatKHR,
	present_modes: [dynamic]vk.PresentModeKHR,
}

@(private)
query_swapchain_support :: proc(device: vk.PhysicalDevice) -> (details: SwapchainSupportDetails) {
	vk.GetPhysicalDeviceSurfaceCapabilitiesKHR(device, vk_ctx.surface, &details.capabilities)

	count: u32
	vk.GetPhysicalDeviceSurfaceFormatsKHR(device, vk_ctx.surface, &count, nil)
	if count != 0 {
		details.formats = make([dynamic]vk.SurfaceFormatKHR, count, context.allocator)
		vk.GetPhysicalDeviceSurfaceFormatsKHR(
			device,
			vk_ctx.surface,
			&count,
			raw_data(details.formats),
		)
	}

	count = 0
	vk.GetPhysicalDeviceSurfacePresentModesKHR(device, vk_ctx.surface, &count, nil)
	if count != 0 {
		details.present_modes = make([dynamic]vk.PresentModeKHR, count, context.allocator)
		vk.GetPhysicalDeviceSurfacePresentModesKHR(
			device,
			vk_ctx.surface,
			&count,
			raw_data(details.present_modes),
		)
	}
	return details
}

@(private)
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

@(private)
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

@(private)
choose_swapchain_extent :: proc(using capabilities: ^vk.SurfaceCapabilitiesKHR) -> vk.Extent2D {
	if (currentExtent.width != max(u32)) {
		return currentExtent // Trick to query if window manager allows us to change extent
	}

	width, height := glfw.GetFramebufferSize(glfw_ctx.window)
	actual_extent := vk.Extent2D {
		clamp(u32(width), minImageExtent.width, maxImageExtent.width),
		clamp(u32(height), maxImageExtent.height, maxImageExtent.height),
	}
	return actual_extent
}

@(private)
create_swapchain :: proc() {
	swapchain_support := query_swapchain_support(vk_ctx.physical_device) // TODO: check if logical device should be passed here
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
		surface          = vk_ctx.surface,
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

	indicies := find_queue_families(vk_ctx.physical_device)
	queue_family_indicies := [?]u32{indicies.graphics_family.?, indicies.presentation_family.?}

	if (indicies.graphics_family != indicies.presentation_family) {
		info.imageSharingMode = .CONCURRENT
		info.queueFamilyIndexCount = 2
		info.pQueueFamilyIndices = raw_data(queue_family_indicies[:])
	} else {
		info.imageSharingMode = .EXCLUSIVE
		info.pQueueFamilyIndices = nil
	}

	if vk.CreateSwapchainKHR(vk_ctx.logical_device, &info, nil, &vk_ctx.swapchain) != .SUCCESS {
		log.fatal("Failed to create swapchain")
	}

	vk.GetSwapchainImagesKHR(vk_ctx.logical_device, vk_ctx.swapchain, &image_count, nil)
	if len(vk_ctx.swapchain_images) == 0 {
		vk_ctx.swapchain_images = make([dynamic]vk.Image, image_count, context.allocator)
	}
	vk.GetSwapchainImagesKHR(
		vk_ctx.logical_device,
		vk_ctx.swapchain,
		&image_count,
		raw_data(vk_ctx.swapchain_images),
	)
	vk_ctx.swapchain_image_format = surface_format.format
	vk_ctx.swapchain_extent = extent
}

@(private)
create_image_views :: proc() {
	if len(vk_ctx.swapchain_image_views) == 0 {
		vk_ctx.swapchain_image_views = make([dynamic]vk.ImageView, len(vk_ctx.swapchain_images))
	}
	for image, i in vk_ctx.swapchain_image_views {
		info := vk.ImageViewCreateInfo {
			sType    = .IMAGE_VIEW_CREATE_INFO,
			image    = vk_ctx.swapchain_images[i],
			viewType = vk.ImageViewType.D2,
			format   = vk_ctx.swapchain_image_format,
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

		if vk.CreateImageView(
			   vk_ctx.logical_device,
			   &info,
			   nil,
			   &vk_ctx.swapchain_image_views[i],
		   ) !=
		   .SUCCESS {
			log.fatal("Failed to create image views")
		}
	}
}

@(private)
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
		vk.DestroyShaderModule(vk_ctx.logical_device, fragment_shader_module, nil)
		vk.DestroyShaderModule(vk_ctx.logical_device, vertex_shader_module, nil)
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

	binding_description := get_binding_description()
	attribute_descriptions := get_attribute_description()

	vertex_input_info := vk.PipelineVertexInputStateCreateInfo {
		sType                           = .PIPELINE_VERTEX_INPUT_STATE_CREATE_INFO,
		vertexBindingDescriptionCount   = 1,
		pVertexBindingDescriptions      = &binding_description,
		vertexAttributeDescriptionCount = len(attribute_descriptions),
		pVertexAttributeDescriptions    = raw_data(attribute_descriptions[:]),
	}

	input_assembley_info := vk.PipelineInputAssemblyStateCreateInfo {
		sType                  = .PIPELINE_INPUT_ASSEMBLY_STATE_CREATE_INFO,
		topology               = .TRIANGLE_LIST,
		primitiveRestartEnable = false,
	}

	viewport := vk.Viewport {
		x        = 0,
		y        = 0,
		width    = f32(vk_ctx.swapchain_extent.width),
		height   = f32(vk_ctx.swapchain_extent.height),
		minDepth = 0,
		maxDepth = 1,
	}

	scissor := vk.Rect2D {
		offset = vk.Offset2D{x = 0, y = 0},
		extent = vk_ctx.swapchain_extent,
	}

	viewport_state := vk.PipelineViewportStateCreateInfo {
		sType         = .PIPELINE_VIEWPORT_STATE_CREATE_INFO,
		viewportCount = 1,
		scissorCount  = 1,
	}

	rasterizer := vk.PipelineRasterizationStateCreateInfo {
		sType                   = .PIPELINE_RASTERIZATION_STATE_CREATE_INFO,
		depthClampEnable        = false,
		rasterizerDiscardEnable = false,
		polygonMode             = .FILL,
		lineWidth               = 1,
		cullMode                = {.BACK},
		frontFace               = .CLOCKWISE,
		depthBiasEnable         = false,
		depthBiasConstantFactor = 0,
		depthBiasClamp          = 0,
		depthBiasSlopeFactor    = 0,
	}

	multisampling := vk.PipelineMultisampleStateCreateInfo {
		sType                 = .PIPELINE_MULTISAMPLE_STATE_CREATE_INFO,
		sampleShadingEnable   = false,
		rasterizationSamples  = {._1},
		minSampleShading      = 1,
		pSampleMask           = nil,
		alphaToCoverageEnable = false,
		alphaToOneEnable      = false,
	}

	color_blend_attachment := vk.PipelineColorBlendAttachmentState {
		colorWriteMask      = {.R, .G, .B, .A},
		blendEnable         = true,
		srcColorBlendFactor = .SRC_ALPHA,
		dstColorBlendFactor = .ONE_MINUS_SRC_ALPHA,
		colorBlendOp        = .ADD,
		srcAlphaBlendFactor = .ONE,
		dstAlphaBlendFactor = .ZERO,
		alphaBlendOp        = .ADD,
	}

	color_blend_state := vk.PipelineColorBlendStateCreateInfo {
		sType           = .PIPELINE_COLOR_BLEND_STATE_CREATE_INFO,
		logicOpEnable   = false,
		logicOp         = .COPY,
		attachmentCount = 1,
		pAttachments    = &color_blend_attachment,
		blendConstants  = {0, 0, 0, 0},
	}

	pipeline_layout_info := vk.PipelineLayoutCreateInfo {
		sType                  = .PIPELINE_LAYOUT_CREATE_INFO,
		setLayoutCount         = 1,
		pSetLayouts            = &vk_ctx.descriptor_set_layout,
		pushConstantRangeCount = 0,
		pPushConstantRanges    = nil,
	}
	if (vk.CreatePipelineLayout(
			   vk_ctx.logical_device,
			   &pipeline_layout_info,
			   nil,
			   &vk_ctx.pipeline_layout,
		   ) !=
		   .SUCCESS) {
		log.fatal("Failed to create pipeline layout")
	}

	info := vk.GraphicsPipelineCreateInfo {
		sType               = .GRAPHICS_PIPELINE_CREATE_INFO,
		stageCount          = 2,
		pStages             = raw_data(shader_stages[:]),
		pVertexInputState   = &vertex_input_info,
		pInputAssemblyState = &input_assembley_info,
		pViewportState      = &viewport_state,
		pRasterizationState = &rasterizer,
		pMultisampleState   = &multisampling,
		pDepthStencilState  = nil,
		pColorBlendState    = &color_blend_state,
		pDynamicState       = &dynamic_state_info,
		layout              = vk_ctx.pipeline_layout,
		renderPass          = vk_ctx.render_pass,
		subpass             = 0,
		basePipelineHandle  = 0,
		basePipelineIndex   = -1,
	}
	if vk.CreateGraphicsPipelines(
		   vk_ctx.logical_device,
		   0,
		   1,
		   &info,
		   nil,
		   &vk_ctx.graphics_pipeline,
	   ) !=
	   .SUCCESS {
		log.fatal("Failed to create graphics pipeline")
	}
}

@(private)
create_shader_module :: proc(data: []u8) -> vk.ShaderModule {
	info := vk.ShaderModuleCreateInfo {
		sType    = .SHADER_MODULE_CREATE_INFO,
		codeSize = len(data),
		pCode    = cast(^u32)raw_data(data),
	}
	shader: vk.ShaderModule
	vk.CreateShaderModule(vk_ctx.logical_device, &info, nil, &shader)
	return shader
}

@(private)
create_render_pass :: proc() {
	color_attachment := vk.AttachmentDescription {
		format         = vk_ctx.swapchain_image_format,
		samples        = {._1},
		loadOp         = .CLEAR,
		storeOp        = .STORE,
		stencilLoadOp  = .DONT_CARE,
		stencilStoreOp = .DONT_CARE,
		initialLayout  = .UNDEFINED,
		finalLayout    = .PRESENT_SRC_KHR,
	}

	color_attachement_ref := vk.AttachmentReference {
		attachment = 0,
		layout     = .COLOR_ATTACHMENT_OPTIMAL,
	}

	subpass := vk.SubpassDescription {
		pipelineBindPoint    = .GRAPHICS,
		colorAttachmentCount = 1,
		pColorAttachments    = &color_attachement_ref,
	}

	dependency := vk.SubpassDependency {
		srcSubpass    = vk.SUBPASS_EXTERNAL,
		dstSubpass    = 0,
		srcStageMask  = {.COLOR_ATTACHMENT_OUTPUT},
		srcAccessMask = {},
		dstStageMask  = {.COLOR_ATTACHMENT_OUTPUT},
		dstAccessMask = {.COLOR_ATTACHMENT_WRITE},
	}

	info := vk.RenderPassCreateInfo {
		sType           = .RENDER_PASS_CREATE_INFO,
		attachmentCount = 1,
		pAttachments    = &color_attachment,
		subpassCount    = 1,
		pSubpasses      = &subpass,
		dependencyCount = 1,
		pDependencies   = &dependency,
	}
	if (vk.CreateRenderPass(vk_ctx.logical_device, &info, nil, &vk_ctx.render_pass) != .SUCCESS) {
		log.fatal("Failed to create render pass")
	}
}

@(private)
create_framebuffers :: proc() {
	if len(vk_ctx.swapchain_framebuffers) == 0 {
		vk_ctx.swapchain_framebuffers = make(
			[dynamic]vk.Framebuffer,
			len(vk_ctx.swapchain_image_views),
		)
	}
	for view, i in vk_ctx.swapchain_image_views {
		attachments := [?]vk.ImageView{view}
		info := vk.FramebufferCreateInfo {
			sType           = .FRAMEBUFFER_CREATE_INFO,
			renderPass      = vk_ctx.render_pass,
			attachmentCount = 1,
			pAttachments    = raw_data(attachments[:]),
			width           = vk_ctx.swapchain_extent.width,
			height          = vk_ctx.swapchain_extent.height,
			layers          = 1,
		}
		if vk.CreateFramebuffer(
			   vk_ctx.logical_device,
			   &info,
			   nil,
			   &vk_ctx.swapchain_framebuffers[i],
		   ) !=
		   .SUCCESS {
			log.fatal("Failed to create framebuffer")
		}
	}
}


@(private)
create_command_pool :: proc() {
	queue_family_indicies := find_queue_families(vk_ctx.physical_device)
	info := vk.CommandPoolCreateInfo {
		sType            = .COMMAND_POOL_CREATE_INFO,
		flags            = {.RESET_COMMAND_BUFFER},
		queueFamilyIndex = queue_family_indicies.graphics_family.?,
	}
	if vk.CreateCommandPool(vk_ctx.logical_device, &info, nil, &vk_ctx.command_pool) != .SUCCESS {
		log.fatal("Failed to create command pool")
	}

}

@(private)
create_command_buffer :: proc() {
	alloc_info := vk.CommandBufferAllocateInfo {
		sType              = .COMMAND_BUFFER_ALLOCATE_INFO,
		commandPool        = vk_ctx.command_pool,
		level              = .PRIMARY,
		commandBufferCount = 1,
	}
	if vk.AllocateCommandBuffers(vk_ctx.logical_device, &alloc_info, &vk_ctx.command_buffer) !=
	   .SUCCESS {
		log.fatal("Failed to allocate command buffers")
	}
}

@(private)
record_command_buffer :: proc(command_buffer: vk.CommandBuffer, image_index: u32) {
	begin_info := vk.CommandBufferBeginInfo {
		sType            = .COMMAND_BUFFER_BEGIN_INFO,
		flags            = {},
		pInheritanceInfo = nil,
	}
	if vk.BeginCommandBuffer(command_buffer, &begin_info) != .SUCCESS {
		log.fatal("Failed to begin recording command buffer")
	}

	clear_color := vk.ClearValue {
		color = {float32 = {0, 0, 0, 1}},
	}

	render_pass_info := vk.RenderPassBeginInfo {
		sType = .RENDER_PASS_BEGIN_INFO,
		renderPass = vk_ctx.render_pass,
		framebuffer = vk_ctx.swapchain_framebuffers[image_index],
		renderArea = vk.Rect2D{offset = {0, 0}, extent = vk_ctx.swapchain_extent},
		clearValueCount = 1,
		pClearValues = &clear_color,
	}
	vk.CmdBeginRenderPass(command_buffer, &render_pass_info, .INLINE)

	vk.CmdBindPipeline(command_buffer, .GRAPHICS, vk_ctx.graphics_pipeline)

	vertex_buffer := [?]vk.Buffer{vk_ctx.vertex_buffer}
	offsets := [?]vk.DeviceSize{0}
	vk.CmdBindVertexBuffers(command_buffer, 0, 1, raw_data(vertex_buffer[:]), raw_data(offsets[:]))
	vk.CmdBindIndexBuffer(command_buffer, vk_ctx.index_buffer, 0, .UINT32)

	viewport := vk.Viewport {
		x        = 0,
		y        = 0,
		width    = f32(vk_ctx.swapchain_extent.width),
		height   = f32(vk_ctx.swapchain_extent.height),
		minDepth = 0,
		maxDepth = 1,
	}
	vk.CmdSetViewport(command_buffer, 0, 1, &viewport)

	scissor := vk.Rect2D {
		offset = {0, 0},
		extent = vk_ctx.swapchain_extent,
	}
	vk.CmdSetScissor(command_buffer, 0, 1, &scissor)
	vk.CmdDrawIndexed(command_buffer, len(indicies), 1, 0, 0, 0)
	vk.CmdEndRenderPass(command_buffer)
	if (vk.EndCommandBuffer(command_buffer) != .SUCCESS) {
		log.fatal("Failed to record command buffer")
	}
}

@(private)
create_sync_objects :: proc() {
	semaphore_info := vk.SemaphoreCreateInfo {
		sType = .SEMAPHORE_CREATE_INFO,
	}
	fence_info := vk.FenceCreateInfo {
		sType = .FENCE_CREATE_INFO,
		flags = {.SIGNALED},
	}
	if vk.CreateSemaphore(
		   vk_ctx.logical_device,
		   &semaphore_info,
		   nil,
		   &vk_ctx.image_avail_semaphore,
	   ) !=
	   .SUCCESS {
		log.fatal("failed to create semaphore")
	}
	if vk.CreateSemaphore(
		   vk_ctx.logical_device,
		   &semaphore_info,
		   nil,
		   &vk_ctx.render_finished_semaphore,
	   ) !=
	   .SUCCESS {
		log.fatal("failed to create semaphore")
	}
	if vk.CreateFence(vk_ctx.logical_device, &fence_info, nil, &vk_ctx.in_flight_fence) !=
	   .SUCCESS {
		log.fatal("failed to create fence")
	}
}

draw_frame :: proc() { 	// TODO: put this as a public window function
	vk.WaitForFences(vk_ctx.logical_device, 1, &vk_ctx.in_flight_fence, true, max(u64))


	image_index: u32
	swapchain_validity := vk.AcquireNextImageKHR(
		vk_ctx.logical_device,
		vk_ctx.swapchain,
		max(u64),
		vk_ctx.image_avail_semaphore,
		0,
		&image_index,
	)

	#partial switch swapchain_validity {
	case .ERROR_OUT_OF_DATE_KHR:
		recreate_swapchain()
	case .SUCCESS, .SUBOPTIMAL_KHR:
	case:
		log.fatal("Failed to create swapchain image")
	}

	vk.ResetFences(vk_ctx.logical_device, 1, &vk_ctx.in_flight_fence)

	//update_uniform_buffer(image_index)

	vk_assert(vk.ResetCommandBuffer(vk_ctx.command_buffer, {}), "Failed to reset command buffer")
	record_command_buffer(vk_ctx.command_buffer, image_index)

	wait_semaphores := [?]vk.Semaphore{vk_ctx.image_avail_semaphore}
	wait_stages := [?]vk.PipelineStageFlags{{.COLOR_ATTACHMENT_OUTPUT}}
	signal_semaphores := [?]vk.Semaphore{vk_ctx.render_finished_semaphore}
	submit_info := vk.SubmitInfo {
		sType                = .SUBMIT_INFO,
		waitSemaphoreCount   = 1,
		pWaitSemaphores      = raw_data(wait_semaphores[:]),
		pWaitDstStageMask    = raw_data(wait_stages[:]),
		commandBufferCount   = 1,
		pCommandBuffers      = &vk_ctx.command_buffer,
		signalSemaphoreCount = 1,
		pSignalSemaphores    = raw_data(signal_semaphores[:]),
	}

	vk_assert(
		vk.QueueSubmit(vk_ctx.graphics_queue, 1, &submit_info, vk_ctx.in_flight_fence),
		"Failed to submit draw command buffer",
	)

	swapchains := [?]vk.SwapchainKHR{vk_ctx.swapchain}
	present_info := vk.PresentInfoKHR {
		sType              = .PRESENT_INFO_KHR,
		waitSemaphoreCount = 1,
		pWaitSemaphores    = raw_data(signal_semaphores[:]),
		swapchainCount     = 1,
		pSwapchains        = raw_data(swapchains[:]),
		pImageIndices      = &image_index,
		pResults           = nil,
	}

	swapchain_validity = vk.QueuePresentKHR(vk_ctx.presentation_queue, &present_info)
	#partial switch swapchain_validity {
	case .ERROR_OUT_OF_DATE_KHR, .SUBOPTIMAL_KHR:
		recreate_swapchain()
	case .SUCCESS:
	case:
		log.fatal("failed to present frame")
	}
}

@(private)
vk_assert :: proc(attempt: vk.Result, message: string, loc := #caller_location) {
	if attempt != .SUCCESS {
		log.fatal(message, location = loc)
		assert(false)
	}
}


@(private)
recreate_swapchain :: proc() {
	w, h := glfw.GetFramebufferSize(glfw_ctx.window)
	for (w * h == 0) {
		w, h = glfw.GetFramebufferSize(glfw_ctx.window)
		glfw.WaitEvents()
	}
	vk.DeviceWaitIdle(vk_ctx.logical_device)
	cleanup_swapchain(false)
	create_swapchain()
	create_image_views()
	create_framebuffers()
}

@(private)
cleanup_swapchain :: proc(closing_app: bool) {
	for buffer in vk_ctx.swapchain_framebuffers {
		vk.DestroyFramebuffer(vk_ctx.logical_device, buffer, nil)
	}
	for image in vk_ctx.swapchain_image_views {
		vk.DestroyImageView(vk_ctx.logical_device, image, nil)
	}
	vk.DestroySwapchainKHR(vk_ctx.logical_device, vk_ctx.swapchain, nil)
	if closing_app {
		delete(vk_ctx.swapchain_framebuffers)
		delete(vk_ctx.swapchain_image_views)
	}
}


@(private)
get_binding_description :: proc() -> vk.VertexInputBindingDescription {
	description := vk.VertexInputBindingDescription {
		binding   = 0,
		stride    = size_of(Vertex),
		inputRate = .VERTEX,
	}
	return description
}

@(private)
get_attribute_description :: proc() -> [2]vk.VertexInputAttributeDescription {
	attributes: [2]vk.VertexInputAttributeDescription
	attributes[0] = {
		binding  = 0,
		location = 0,
		format   = .R32G32_SFLOAT,
		offset   = u32(offset_of(Vertex, pos)),
	}
	attributes[1] = {
		binding  = 0,
		location = 1,
		format   = .R32G32B32_SFLOAT,
		offset   = u32(offset_of(Vertex, color)),
	}
	return attributes
}

@(private)
create_buffer :: proc(
	size: vk.DeviceSize,
	usage: vk.BufferUsageFlags,
	properties: vk.MemoryPropertyFlags,
	buffer: ^vk.Buffer,
	buffer_memory: ^vk.DeviceMemory,
) {
	info := vk.BufferCreateInfo {
		sType       = .BUFFER_CREATE_INFO,
		size        = size,
		usage       = usage,
		sharingMode = .EXCLUSIVE,
	}
	vk_assert(
		vk.CreateBuffer(vk_ctx.logical_device, &info, nil, buffer),
		"Failed to create vertex buffer",
	)

	memory_reqs: vk.MemoryRequirements
	vk.GetBufferMemoryRequirements(vk_ctx.logical_device, buffer^, &memory_reqs)

	alloc_info := vk.MemoryAllocateInfo {
		sType           = .MEMORY_ALLOCATE_INFO,
		allocationSize  = memory_reqs.size,
		memoryTypeIndex = find_memory_type(memory_reqs.memoryTypeBits, properties),
	}
	vk_assert(
		vk.AllocateMemory(vk_ctx.logical_device, &alloc_info, nil, buffer_memory),
		"Failed to allocate memory for the vertex buffer",
	)
	vk.BindBufferMemory(vk_ctx.logical_device, buffer^, buffer_memory^, 0)
}

@(private)
find_memory_type :: proc(type_filter: u32, properties: vk.MemoryPropertyFlags) -> u32 {
	mem_properties: vk.PhysicalDeviceMemoryProperties
	vk.GetPhysicalDeviceMemoryProperties(vk_ctx.physical_device, &mem_properties)

	for i in 0 ..< mem_properties.memoryTypeCount {
		if (type_filter & (1 << i) != 0) &&
		   (mem_properties.memoryTypes[i].propertyFlags & properties == properties) {
			return i
		}
	}
	log.fatal("Failed to find a suitable memory type")
	return 0
}

@(private)
create_vertex_buffer :: proc() {
	buffer_size: vk.DeviceSize = size_of(Vertex) * len(vertices)
	staging_buffer: vk.Buffer
	staging_buffer_memory: vk.DeviceMemory
	create_buffer(
		buffer_size,
		{.TRANSFER_SRC},
		{.HOST_VISIBLE, .HOST_COHERENT},
		&staging_buffer,
		&staging_buffer_memory,
	)

	data: rawptr
	vk.MapMemory(vk_ctx.logical_device, staging_buffer_memory, 0, buffer_size, {}, &data)
	mem.copy(data, &vertices, int(buffer_size))
	vk.UnmapMemory(vk_ctx.logical_device, staging_buffer_memory)
	create_buffer(
		buffer_size,
		{.TRANSFER_DST, .VERTEX_BUFFER},
		{.DEVICE_LOCAL},
		&vk_ctx.vertex_buffer,
		&vk_ctx.vertex_buffer_memory,
	)
	copy_buffer(staging_buffer, vk_ctx.vertex_buffer, buffer_size)
	vk.DestroyBuffer(vk_ctx.logical_device, staging_buffer, nil)
	vk.FreeMemory(vk_ctx.logical_device, staging_buffer_memory, nil)
}

@(private)
create_index_buffer :: proc() {
	buffer_size: vk.DeviceSize = size_of(u32) * len(indicies)
	staging_buffer: vk.Buffer
	staging_buffer_memory: vk.DeviceMemory
	create_buffer(
		buffer_size,
		{.TRANSFER_SRC},
		{.HOST_VISIBLE, .HOST_COHERENT},
		&staging_buffer,
		&staging_buffer_memory,
	)

	data: rawptr
	vk.MapMemory(vk_ctx.logical_device, staging_buffer_memory, 0, buffer_size, {}, &data)
	mem.copy(data, &indicies, int(buffer_size))
	vk.UnmapMemory(vk_ctx.logical_device, staging_buffer_memory)
	create_buffer(
		buffer_size,
		{.TRANSFER_DST, .INDEX_BUFFER},
		{.DEVICE_LOCAL},
		&vk_ctx.index_buffer,
		&vk_ctx.index_buffer_memory,
	)
	copy_buffer(staging_buffer, vk_ctx.index_buffer, buffer_size)
	vk.DestroyBuffer(vk_ctx.logical_device, staging_buffer, nil)
	vk.FreeMemory(vk_ctx.logical_device, staging_buffer_memory, nil)
}

@(private)
copy_buffer :: proc(src, dest: vk.Buffer, size: vk.DeviceSize) {
	alloc_info := vk.CommandBufferAllocateInfo {
		sType              = .COMMAND_BUFFER_ALLOCATE_INFO,
		level              = .PRIMARY,
		commandPool        = vk_ctx.command_pool,
		commandBufferCount = 1,
	}
	command_buffer: vk.CommandBuffer
	vk.AllocateCommandBuffers(vk_ctx.logical_device, &alloc_info, &command_buffer)
	begin_info := vk.CommandBufferBeginInfo {
		sType = .COMMAND_BUFFER_BEGIN_INFO,
		flags = {.ONE_TIME_SUBMIT},
	}
	vk.BeginCommandBuffer(command_buffer, &begin_info)
	copy_region := vk.BufferCopy {
		srcOffset = 0,
		dstOffset = 0,
		size      = size,
	}
	vk.CmdCopyBuffer(command_buffer, src, dest, 1, &copy_region)
	vk.EndCommandBuffer(command_buffer)
	submit_info := vk.SubmitInfo {
		sType              = .SUBMIT_INFO,
		commandBufferCount = 1,
		pCommandBuffers    = &command_buffer,
	}
	vk.QueueSubmit(vk_ctx.graphics_queue, 1, &submit_info, 0)
	vk.QueueWaitIdle(vk_ctx.graphics_queue)
	vk.FreeCommandBuffers(vk_ctx.logical_device, vk_ctx.command_pool, 1, &command_buffer)
}

@(private)
create_descriptor_set_layout :: proc() {
	ubo_layout_binding := vk.DescriptorSetLayoutBinding {
		binding            = 0,
		descriptorType     = .UNIFORM_BUFFER,
		descriptorCount    = 1,
		stageFlags         = {.VERTEX},
		pImmutableSamplers = nil,
	}
	layout_info := vk.DescriptorSetLayoutCreateInfo {
		sType        = .DESCRIPTOR_SET_LAYOUT_CREATE_INFO,
		bindingCount = 1,
		pBindings    = &ubo_layout_binding,
	}
	vk_assert(
		vk.CreateDescriptorSetLayout(
			vk_ctx.logical_device,
			&layout_info,
			nil,
			&vk_ctx.descriptor_set_layout,
		),
		"Failed to create descriptor set layout",
	)
}

@(private)
create_uniform_buffer :: proc() {
	buffer_size := size_of(UBO)
	vk_ctx.uniform_buffers = make([dynamic]vk.Buffer, 5)
}

@(private)
update_uniform_buffer :: proc(image: u32) {
	curr_time := time.now()
	time_running := time.duration_milliseconds(time.diff(vk_ctx.start_time, curr_time))
	ubo: UBO
	ubo.model = linalg.matrix4_rotate_f32(f32(time_running), [3]f32{0, 0, 1})
	ubo.view = linalg.matrix4_look_at_f32([3]f32{2, 2, 2}, [3]f32{0, 0, 0}, [3]f32{0, 0, 1})
	ubo.proj = linalg.matrix4_perspective_f32(
		math.to_radians_f32(45),
		f32(vk_ctx.swapchain_extent.width / vk_ctx.swapchain_extent.height),
		.1,
		10,
	)
	if len(vk_ctx.uniform_buffers_mapped) <= int(image) {
		vk_ctx.uniform_buffers_mapped = make([dynamic]rawptr, image + 1)
	}
	mem.copy(vk_ctx.uniform_buffers_mapped[image], &ubo, size_of(UBO))
}

