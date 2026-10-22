/*
 * This file is part of Terminal.app.
 * Copyright (C) 2026 Terminal contributors.
 * This program is free software: you can redistribute it and/or modify it
 * under the terms of the GNU General Public License, version 3 or later.
 * This program is distributed WITHOUT ANY WARRANTY; without even the implied
 * warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
 * See <https://www.gnu.org/licenses/> for a copy of the license.
 */

#import <Foundation/Foundation.h>
#import <AppKit/NSEvent.h>
#import "Terminal.h"
#include <vterm.h>

@interface TerminalParser_VTerm : NSObject <TerminalParser>
{
  id<TerminalScreen> ts;
  VTerm *terminal;
  VTermScreen *screen;
  int width, height;
  NSMutableData *title, *iconTitle;
}

@end
