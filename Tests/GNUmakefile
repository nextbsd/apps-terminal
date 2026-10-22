ifeq ($(GNUSTEP_MAKEFILES),)
GNUSTEP_MAKEFILES := $(shell gnustep-config --variable=GNUSTEP_MAKEFILES)
endif
include $(GNUSTEP_MAKEFILES)/common.make
TOOL_NAME = EmulatorTests ViewTests
EmulatorTests_OBJC_FILES = main.m ../TerminalParser_VTerm.m
EmulatorTests_C_FILES = $(wildcard ../libvterm/src/*.c)
EmulatorTests_INCLUDE_DIRS = -I.. -I../libvterm/include
EmulatorTests_CFLAGS = -std=c99
EmulatorTests_TOOL_LIBS = -lgnustep-gui
ViewTests_OBJC_FILES = gui.m ../TerminalView.m ../TerminalParser_VTerm.m ../TerminalViewPrefs.m ../StringClasses.m ../Label.m
ViewTests_C_FILES = $(wildcard ../libvterm/src/*.c)
ViewTests_INCLUDE_DIRS = -I.. -I../libvterm/include
ViewTests_CFLAGS = -std=c99
ViewTests_TOOL_LIBS = -lgnustep-gui -lutil
include $(GNUSTEP_MAKEFILES)/tool.make
check:: all
	./obj/EmulatorTests

check-gui:: all
	xvfb-run -a ./obj/ViewTests
