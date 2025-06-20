# Engine Cheatsheet
## Core
### Window
[Initilalise a window with given dimensions width*height and header title, including a vulkan context]()

`init_window :: (width: i32, height: i32, title: string) -> ()`

[Check to see if window should close i.e. when ESC is pressed, note: Currently also draws a frame and polls for input]()

`window_should_close :: () -> bool`

[Close a window, and clean the vulkan context]()

`close_window :: () -> ()`

[Maximise the window, seems to keep current resoloution]()

`maximise_window :: () -> ()`

[Make the window full screen borderless]()

`borderless_window :: () -> ()`

[Set a new title for the window]()

`set_window_title :: (title: string) -> ()`

### Logger
[Create a console and file logger at filepath, will but additional debug info into file to keep console cleaner]()

`init_logger:: (filepath: string) -> log.Logger`

### Tracker
[Create a tracking allocator and return it for assigning to the context while including a reference to it]()

`init_tracker :: () -> (^mem.Tracking_Allocator, mem.Allocactor)`

[Check a tracking allocator]()

`check_tracker :: (^mem.Tracking_Allocator) -> ()`

[Check and destroy a tracking allocator]()

`destroy_tracker :: (^mem.Tracking_Allocator) -> ()`
