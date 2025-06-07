package core

import "base:runtime"
import "core:fmt"
import "core:log"
import "core:slice"
import "core:strings"
import "vendor:glfw"
import vk "vendor:vulkan"

// Package Variables
ctx: runtime.Context
window: glfw.WindowHandle
instance: vk.Instance
debugMessenger: vk.DebugUtilsMessengerEXT
validationLayers :: []cstring{"VK_LAYER_KHRONOS_validation"}

initWindow :: proc(width: i32, height: i32, title: string) {
	ctx = context
	assert(window == nil)
	glfw.Init()
	glfw.WindowHint(glfw.CLIENT_API, glfw.NO_API)
	glfw.WindowHint(glfw.RESIZABLE, glfw.FALSE)
	window = glfw.CreateWindow(width, height, strings.clone_to_cstring(title), nil, nil)
	assert(window != nil)
	initVulkan()
	fmt.println("Initialised Vulkan")
}

windowShouldClose :: proc() -> b32 {
	glfw.PollEvents()

	if glfw.GetKey(window, glfw.KEY_ESCAPE) == glfw.PRESS {
		return true
	}
	return glfw.WindowShouldClose(window)
}

closeWindow :: proc() {
	assert(window != nil)
	assert(instance != nil)
	vk.DestroyDebugUtilsMessengerEXT(instance, debugMessenger, nil)
	vk.DestroyInstance(instance, nil)
	instance = nil
	glfw.DestroyWindow(window)
	glfw.Terminate()
	window = nil
}

@(private = "file")
initVulkan :: proc() {
	createInstance()
	vk.load_proc_addresses_instance(instance)
	setupDebugMessenger()
}

@(private = "file")
createInstance :: proc() {
	// Load function pointers check odin example for this
	vk.load_proc_addresses_global(rawptr(glfw.GetInstanceProcAddress))
	assert(vk.CreateInstance != nil)

	checkValidationLayer()

	appInfo := vk.ApplicationInfo {
		sType              = vk.StructureType.APPLICATION_INFO,
		pApplicationName   = "Hello Triangle",
		applicationVersion = vk.MAKE_VERSION(1, 0, 0),
		pEngineName        = "No Engine",
		engineVersion      = vk.MAKE_VERSION(1, 0, 0),
		apiVersion         = vk.API_VERSION_1_0,
	}

	// extensions := slice.clone_to_dynamic(glfw.GetRequiredInstanceExtensions())
	extensions := getRequiredExtensions()
	fmt.println(extensions)

	dci: vk.DebugUtilsMessengerCreateInfoEXT
	createInfo := vk.InstanceCreateInfo {
		sType                   = vk.StructureType.INSTANCE_CREATE_INFO,
		pApplicationInfo        = &appInfo,
		enabledExtensionCount   = u32(len(extensions)),
		ppEnabledExtensionNames = raw_data(extensions),
		enabledLayerCount       = u32(len(validationLayers)),
		ppEnabledLayerNames     = raw_data(validationLayers),
	}

	populateDebugMessengerCreateInfo(&dci)
	createInfo.pNext = &dci

	assert(vk.CreateInstance(&createInfo, nil, &instance) == vk.Result.SUCCESS)
}

@(private = "file")
checkValidationLayer :: proc() -> bool {
	layerCount: u32
	vk.EnumerateInstanceLayerProperties(&layerCount, nil)
	availableLayers := make([]vk.LayerProperties, layerCount)
	vk.EnumerateInstanceLayerProperties(&layerCount, raw_data(availableLayers))
	for layerName in validationLayers {
		layerFound: bool
		for &layerProperties in availableLayers { 	// Add & to make [256]byte addressable
			availableLayer := strings.clone_to_cstring(
				strings.trim_null(transmute(string)(layerProperties.layerName[:])),
			)
			if layerName == availableLayer {
				layerFound = true
			}
		}
		assert(layerFound == true)
	}
	return true
}

@(private = "file")
getRequiredExtensions :: proc() -> []cstring {
	glfwExtensions := glfw.GetRequiredInstanceExtensions()
	cstr: cstring = vk.EXT_DEBUG_UTILS_EXTENSION_NAME
	glfwExt := [dynamic]cstring{}
	append(&glfwExt, ..glfwExtensions[:])
	append(&glfwExt, cstr)
	return glfwExt[:]
}

@(private = "file")
debugCallback :: proc "system" (
	mSev: vk.DebugUtilsMessageSeverityFlagsEXT,
	mType: vk.DebugUtilsMessageTypeFlagsEXT,
	pCallbackData: ^vk.DebugUtilsMessengerCallbackDataEXT,
	pUserData: rawptr,
) -> b32 {
	context = ctx
	fmt.println("Validation Layer:", pCallbackData.pMessage)
	return false
}

@(private = "file")
setupDebugMessenger :: proc() {
	createInfo: vk.DebugUtilsMessengerCreateInfoEXT
	populateDebugMessengerCreateInfo(&createInfo)
	assert(
		vk.CreateDebugUtilsMessengerEXT(instance, &createInfo, nil, &debugMessenger) ==
		vk.Result.SUCCESS,
	)
}

@(private = "file")
populateDebugMessengerCreateInfo :: proc(ci: ^vk.DebugUtilsMessengerCreateInfoEXT) {
	ci.sType = .DEBUG_UTILS_MESSENGER_CREATE_INFO_EXT
	ci.messageSeverity = vk.DebugUtilsMessageSeverityFlagsEXT{.VERBOSE, .WARNING, .ERROR}
	ci.messageType = vk.DebugUtilsMessageTypeFlagsEXT{.GENERAL, .VALIDATION, .PERFORMANCE}
	ci.pfnUserCallback = debugCallback
	ci.pUserData = nil
}

