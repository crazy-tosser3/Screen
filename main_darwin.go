package main

/*
#cgo CFLAGS: -fobjc-arc
#cgo LDFLAGS: -framework Cocoa -framework AVFoundation -framework CoreMedia -framework CoreVideo -framework QuartzCore
#include "bridge.h"
*/
import "C"

import "runtime"

func main() {
	runtime.LockOSThread()
	defer runtime.UnlockOSThread()
	C.ScreenRun()
}
