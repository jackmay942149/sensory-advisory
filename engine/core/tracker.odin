package core

import "base:runtime"
import "core:log"
import "core:mem"

init_tracker :: proc(ctx: ^runtime.Context) -> (tracker: mem.Tracking_Allocator) {
	mem.tracking_allocator_init(&tracker, context.allocator)
	return tracker
}

check_tracker :: proc(tracker: mem.Tracking_Allocator) {
	log.info("Checking tracker allocator")
	for _, elem in tracker.allocation_map {
		log.warn("Allocation not freed:", elem.size, "bytes @", elem.location)
	}
	for elem in tracker.bad_free_array {
		log.warn("Incorrect frees:", elem.memory, "@", elem.location)
	}
}

destroy_tracker :: proc(tracker: ^mem.Tracking_Allocator) {
	check_tracker(tracker^)
	// assert(len(tracker.allocation_map) == 0)
	assert(len(tracker.bad_free_array) == 0)
}

