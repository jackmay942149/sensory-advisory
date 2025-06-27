package core

import "base:runtime"
import "core:log"
import "core:os"

Logger_User :: enum {
	All,
	Jack,
	Mitch,
}

Logger_Topic :: enum {
	All,
	Core,
	Graphics,
	Input,
}

Logger_Context :: struct {
	user:  Logger_User,
	topic: Logger_Topic,
}

logger_ctx: Logger_Context

init_logger :: proc(
	file: string,
	user := Logger_User.All,
	topic := Logger_Topic.All,
) -> log.Logger {
	logger_ctx = {user, topic}
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

user_log :: proc(user: Logger_User, log_level := log.Level.Info, args: ..any) {
	if logger_ctx.user != .All && user != logger_ctx.user && user != .All {
		return
	}
	switch log_level {
	case .Debug:
		log.debug(user, ": ", args)
	case .Info:
		log.info(user, ": ", args)
	case .Warning:
		log.warn(user, ": ", args)
	case .Error:
		log.error(user, ": ", args)
	case .Fatal:
		log.fatal(user, ": ", args)
	}
}

topic_log :: proc(topic: Logger_Topic, log_level := log.Level.Info, args: ..any) {
	if logger_ctx.topic != .All && topic != logger_ctx.topic && topic != .All {
		return
	}
	switch log_level {
	case .Debug:
		log.debug(topic, ": ", args)
	case .Info:
		log.info(topic, ": ", args)
	case .Warning:
		log.warn(topic, ": ", args)
	case .Error:
		log.error(topic, ": ", args)
	case .Fatal:
		log.fatal(topic, ": ", args)
	}
}

