package core

import "base:runtime"
import "core:log"
import "core:os"

@(private = "file")
f_info_log, f_debug_log, f_logger: log.Logger

init_logger :: proc(ctx: ^runtime.Context, file: string) {
	info_opt := log.Options {
		.Level,
		.Short_File_Path,
		.Line,
		.Procedure,
		.Terminal_Color,
		.Thread_Id,
	}

	f_info_log = log.create_console_logger(.Info, info_opt, "", context.allocator)
	context.logger = f_info_log

	os.remove(file)
	handle, err := os.open(file, os.O_CREATE | os.O_WRONLY) // TODO: Bug here i think i need to clear the file contents
	if err != nil {
		log.fatal("Failed to open file logger")
	}

	f_debug_log = log.create_file_logger(
		handle,
		.Debug,
		log.Default_File_Logger_Opts,
		"",
		context.allocator,
	)

	f_logger = log.create_multi_logger(f_debug_log, f_info_log, allocator = context.allocator)
	ctx.logger = f_logger
	context.logger = f_logger
	log.info("Created logger")
}

close_logger :: proc() {
	log.destroy_multi_logger(f_logger)
	log.destroy_console_logger(f_info_log)
	log.destroy_file_logger(f_debug_log)
}

