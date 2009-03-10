# copyright 2002-2003 Alexander Malmberg <alexander@malmberg.org>
# copyright 2008-2009 Riccardo Mottola
#
# This file is a part of Terminal.app. Terminal.app is free software; you
# can redistribute it and/or modify it under the terms of the GNU General
# Public License as published by the Free Software Foundation; version 2
# of the License. See COPYING or main.m for more information.


include $(GNUSTEP_MAKEFILES)/common.make

APP_NAME = Terminal
PACKAGE_NAME = Terminal
VERSION = 0.9.4

ADDITIONAL_OBJCFLAGS += -O2 

# Useful warnings:
#	-W -Wformat=2 -Wno-sign-compare -Wpointer-arith \
#	-Wbad-function-cast -Wcast-align -Wwrite-strings -Wstrict-prototypes \
#	-Wmissing-prototypes -Wmissing-declarations \
#	-Wnested-externs -Wno-unused-parameter

Terminal_OBJC_FILES = \
	main.m \
	\
	Services.m \
	ServicesPrefs.m \
	ServicesParameterWindowController.m \
	\
	TerminalWindow.m \
	TerminalWindowPrefs.m \
	\
	TerminalView.m \
	TerminalViewPrefs.m \
	\
	TerminalParser_Linux.m \
	TerminalParser_LinuxPrefs.m \
	\
	PreferencesWindowController.m \
	autokeyviewchain.m \
	\
	Label.m



ifeq ($(findstring solaris, $(GNUSTEP_TARGET_OS)), solaris)
 Terminal_LDFLAGS = 
else
 Terminal_LDFLAGS = -lutil
endif

Terminal_LOCALIZED_RESOURCE_FILES = Localizable.strings
Terminal_LANGUAGES = English Swedish German French Spanish Hungarian Turkish \
	Norwegian Russian

Terminal_APPLICATION_ICON = Terminal.tiff
Terminal_RESOURCE_FILES = \
	Terminal.tiff DefaultTerminalServices.svcs \
	cursor_line.tiff cursor_stroked.tiff cursor_filled.tiff \
	cursor_inverted.tiff

MAKE_STRINGS_OPTIONS = --aggressive-match --aggressive-remove


GNUSTEP_INSTALLATION_DIR=$(GNUSTEP_SYSTEM_ROOT)


include $(GNUSTEP_MAKEFILES)/application.make

