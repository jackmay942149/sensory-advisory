package core

import "base:runtime"
import "core:log"
import "core:os"

init_logger :: proc(file: string) -> log.Logger {
	// Create terminal logger
	info_opt := log.Options {
		.Level,
		.Short_File_Path,
		.Line,
		.Procedure,
		.Terminal_Color,
		.Thread_Id,
	}
	info_log := log.create_console_logger(.Info, info_opt, "", context.allocator)
	context.logger = info_log

	// Create file logger
	os.remove(file)
	handle, err := os.open(file, os.O_CREATE | os.O_WRONLY) // TODO: Bug here i think i need to clear the file contents
	if err != nil {
		log.fatal("Failed to open file logger")
	}
	debug_log := log.create_file_logger(
		handle,
		.Debug,
		log.Default_File_Logger_Opts,
		"",
		context.allocator,
	)

	logger := log.create_multi_logger(debug_log, info_log, allocator = context.allocator)
	log.info("Created logger")
	return logger
}

