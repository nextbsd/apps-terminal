/*
 * This file is part of Terminal.app.
 * Copyright (C) 2026 Terminal contributors.
 * This program is free software: you can redistribute it and/or modify it
 * under the terms of the GNU General Public License, version 3 or later.
 * This program is distributed WITHOUT ANY WARRANTY; without even the implied
 * warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
 * See <https://www.gnu.org/licenses/> for a copy of the license.
 */

/*
Copyright 2002 Alexander Malmberg <alexander@malmberg.org>
          2012 Free Software Foundation, Inc

Authros: Alexander Malmberg
         Riccardo Mottola

This file is a part of Terminal.app. Terminal.app is free software; you
can redistribute it and/or modify it under the terms of the GNU General
Public License as published by the Free Software Foundation; version 2
of the License. See COPYING or main.m for more information.
*/

#import <AppKit/NSWindowController.h>

#import "PrefBox.h"

@class NSView,NSBox;

@interface PreferencesWindowController : NSWindowController
{
	NSView *button_box;
	NSBox *pref_box;

	NSObject<PrefBox> *current;

	NSMutableArray *pref_boxes;
	NSMutableArray *pref_buttons;
}

-(void) addPrefBox: (NSObject<PrefBox> *)pb;

@end


