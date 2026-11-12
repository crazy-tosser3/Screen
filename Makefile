APP := Screen.app
BINARY := $(APP)/Contents/MacOS/Screen

.PHONY: all build run clean

all: build

build:
	mkdir -p $(APP)/Contents/MacOS
	go build -trimpath -o $(BINARY) .
	cp Info.plist $(APP)/Contents/Info.plist
	codesign --force --deep --sign - $(APP)

run: build
	open $(APP)

clean:
	rm -rf $(APP)
