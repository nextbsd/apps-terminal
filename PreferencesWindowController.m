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
Copyright 2002, 2003 Alexander Malmberg <alexander@malmberg.org>
Copyright 2009-2012 Free Software Foundation Inc.

Authors: Alexander Malmberg
         Riccardo Mottola

This file is a part of Terminal.app. Terminal.app is free software; you
can redistribute it and/or modify it under the terms of the GNU General
Public License as published by the Free Software Foundation; version 2
of the License. See COPYING or main.m for more information.
*/

#import <Foundation/NSObject.h>
#import <Foundation/NSInvocation.h>
#import <Foundation/NSBundle.h>
#import <AppKit/NSWindow.h>
#import <AppKit/NSButton.h>
#import <AppKit/NSScrollView.h>
#import <AppKit/NSClipView.h>
#import <AppKit/NSTableView.h>
#import <AppKit/NSTableColumn.h>
#import <AppKit/NSPanel.h>
#import <AppKit/NSBox.h>
#import <AppKit/NSImage.h>
#import <AppKit/NSColor.h>
#import <AppKit/NSBezierPath.h>
#include <math.h>
#import <GNUstepGUI/GSHbox.h>
#import <GNUstepGUI/GSVbox.h>

#import "autokeyviewchain.h"
#import "PreferencesWindowController.h"
#import "PrefBox.h"


/* Small vector icons share the same canvas and stroke weight. */
static void
preferenceIconLine (CGFloat x1, CGFloat y1, CGFloat x2, CGFloat y2)
{
  NSBezierPath *path = [NSBezierPath bezierPath];
  [path setLineWidth: 2];
  [path moveToPoint: NSMakePoint(x1,y1)];
  [path lineToPoint: NSMakePoint(x2,y2)];
  [path stroke];
}

static NSImage *
preferenceIcon (NSString *category)
{
  NSImage *image = AUTORELEASE([[NSImage alloc] initWithSize: NSMakeSize(36,36)]);
  NSColor *ink = [NSColor colorWithCalibratedRed: .18 green: .27 blue: .34 alpha: 1];
  NSColor *accent = [NSColor colorWithCalibratedRed: .25 green: .58 blue: .72 alpha: 1];
  NSBezierPath *path;
  int row, column;
  [image lockFocus];
  [ink set];
  if ([category isEqual: @"TerminalViewKeyboardPrefs"])
    {
      path = [NSBezierPath bezierPathWithRoundedRect: NSMakeRect(2,7,32,22)
                                           xRadius: 3 yRadius: 3];
      [path setLineWidth: 2];
      [path stroke];
      [accent set];
      for (row=0; row<2; row++)
        for (column=0; column<5; column++)
          [[NSBezierPath bezierPathWithRect:
            NSMakeRect(6+column*5,18+row*5,3,3)] fill];
      [[NSBezierPath bezierPathWithRect: NSMakeRect(10,11,16,3)] fill];
    }
  else if ([category isEqual: @"TerminalServicesPrefs"])
    {
      /* Gear: services and automation. */
      for (column=0; column<8; column++)
        {
          CGFloat a=column*M_PI/4;
          preferenceIconLine(18+11*cos(a),18+11*sin(a),
                             18+16*cos(a),18+16*sin(a));
        }
      path = [NSBezierPath bezierPathWithOvalInRect: NSMakeRect(7,7,22,22)];
      [accent set];
      [path fill];
      [ink set];
      [path setLineWidth: 2];
      [path stroke];
      path = [NSBezierPath bezierPathWithOvalInRect: NSMakeRect(14,14,8,8)];
      [path stroke];
    }
  else
    {
      if ([category isEqual: @"TerminalWindowPrefs"])
        {
          path = [NSBezierPath bezierPathWithRect: NSMakeRect(9,12,25,21)];
          [path setLineWidth: 2];
          [path stroke];
        }
      path = [NSBezierPath bezierPathWithRoundedRect: NSMakeRect(3,9,27,21)
                                           xRadius: 2 yRadius: 2];
      [[NSColor colorWithCalibratedWhite: .94 alpha: 1] set];
      [path fill];
      [ink set];
      [path setLineWidth: 2];
      [path stroke];
      if ([category isEqual: @"TerminalViewShellPrefs"])
        {
          [accent set];
          preferenceIconLine(8,24,13,20);
          preferenceIconLine(13,20,8,16);
          preferenceIconLine(16,15,24,15);
        }
      else if ([category isEqual: @"TerminalWindowPrefs"])
        {
          [accent set];
          preferenceIconLine(4,25,29,25);
          preferenceIconLine(7,28,10,28);
        }
      else
        {
          [accent set];
          [[NSBezierPath bezierPathWithRect: NSMakeRect(7,13,19,13)] fill];
          [ink set];
          preferenceIconLine(16,9,16,4);
          preferenceIconLine(10,3,22,3);
        }
    }
  [image unlockFocus];
  return image;
}

/*
Changing the font in TerminalViewPrefs won't work unless the panel can be
the main window (the font panel gets confused about where to send the
-changeFont:), hence this class. When per-window preferences are done, this
won't be necessary.
*/
@interface PreferencesPanel : NSPanel

@end

@implementation PreferencesPanel
-(BOOL) canBecomeMainWindow
{
	return YES;
}

@end


@implementation PreferencesWindowController

-(void) save: (id)sender
{
	[pref_boxes makeObjectsPerformSelector: @selector(save)];
}

-(void) revert: (id)sender
{
	[pref_boxes makeObjectsPerformSelector: @selector(revert)];
}


- init
{
	NSWindow *win;

	win=[[PreferencesPanel alloc] initWithContentRect: NSMakeRect(100,100,290,400)
		styleMask: NSClosableWindowMask|NSTitledWindowMask|NSResizableWindowMask|NSMiniaturizableWindowMask
		backing: NSBackingStoreRetained
		defer: YES];
	if (!(self=[super initWithWindow: win])) return nil;

	{
		GSVbox *vbox;

		vbox=[[GSVbox alloc] init];
		[vbox setBorder: 4];
		[vbox setDefaultMinYMargin: 4];

		{
			NSButton *b;
			GSHbox *hbox;

			hbox=[[GSHbox alloc] init];
			[hbox setDefaultMinXMargin: 4];
			[hbox setAutoresizingMask: NSViewMinXMargin];

			b=[[NSButton alloc] init];
			[b setTitle: _(@"Revert")];
			[b setTarget: self];
			[b setAction: @selector(revert:)];
			[b sizeToFit];
			[hbox addView: b];
			RELEASE(b);

			b=[[NSButton alloc] init];
			[b setTitle: _(@"Apply and save")];
			[b setKeyEquivalent: @"\r"];
			[b setTarget: self];
			[b setAction: @selector(save:)];
			[b sizeToFit];
			[hbox addView: b];
			RELEASE(b);

			[vbox addView: hbox  enablingYResizing: NO];
			RELEASE(hbox);
		}

		{
			pref_box=[[NSBox alloc] initWithFrame: NSMakeRect(0,0,1,1)];
			[pref_box setTitle: @"<invalid>"];
			[pref_box setAutoresizingMask: NSViewWidthSizable|NSViewHeightSizable];
			[pref_box setAutoresizesSubviews: YES];
			[vbox addView: pref_box  enablingYResizing: YES];
		}

		{
			NSScrollView *sv;
			NSSize s;

			button_box=[[NSView alloc] initWithFrame: NSMakeRect(0,0,1,88)];

			s=[NSScrollView frameSizeForContentSize: NSMakeSize(1,88)
				hasHorizontalScroller: NO
				hasVerticalScroller: NO
				borderType: NSBezelBorder];

			sv=[[NSScrollView alloc] initWithFrame: NSMakeRect(0,0,1,s.height)];
			[sv setDocumentView: button_box];
			[sv setAutoresizingMask: NSViewWidthSizable|NSViewHeightSizable];
			[sv setHasHorizontalScroller: NO];
			[sv setBorderType: NSBezelBorder];

			[vbox addView: sv  enablingYResizing: NO];
			DESTROY(sv);
		}

		[win setContentView: vbox];
		RELEASE(vbox);
	}
	[win setDelegate: self];
	[win setTitle: _(@"Preferences")];

	[win setMinSize: NSMakeSize(410,430)];
	[win setFrameUsingName: @"Preferences"];
	[win setFrameAutosaveName: @"Preferences"];

	[win autoSetupKeyViewChain];

	RELEASE(win);

	pref_boxes=[[NSMutableArray alloc] init];
	pref_buttons=[[NSMutableArray alloc] init];

	return self;
}

-(void) dealloc
{
	if (current)
	{
		[current willHide];
		current=nil;
	}

	DESTROY(pref_boxes);
	DESTROY(pref_buttons);
	DESTROY(button_box);
	DEALLOC;
}


-(void) _displayBox: (NSObject<PrefBox> *)pb
{
  NSUInteger idx;

  idx = [pref_boxes indexOfObjectIdenticalTo: pb];
  if (idx==NSNotFound)
    return;

  if (current==pb)
    return;

	if (current)
	{
		[[pref_buttons objectAtIndex: [pref_boxes indexOfObjectIdenticalTo: current]] setState: 0];
		[current willHide];
		current=nil;
	}

	[[pref_buttons objectAtIndex: idx] setState: 1];
	[pref_box setTitle: [pb name]];
	[pref_box setContentView: [pb willShow]];
	current=pb;

	[[self window] autoSetupKeyViewChain];
}


-(void) _displayBoxButton: (id)sender
{
  NSUInteger idx;

  idx = [pref_buttons indexOfObjectIdenticalTo: sender];
  if (idx==NSNotFound)
    return;

  if ([pref_boxes objectAtIndex: idx]==current)
    {
      [sender setState: 1];
      return;
    }

  [self _displayBox: [pref_boxes objectAtIndex: idx]];
}

-(void) addPrefBox: (NSObject<PrefBox> *)pb
{
	NSButton *b=[[NSButton alloc] init];

	[pref_boxes addObject: pb];
	[pref_buttons addObject: b];

	[pb setupButton: b];
  [b setImage: preferenceIcon(NSStringFromClass([pb class]))];
  [b setImagePosition: NSImageAbove];
  [b setAutoresizingMask: NSViewNotSizable];
	[b setTarget: self];
	[b setAction: @selector(_displayBoxButton:)];
	[b setButtonType: NSPushOnPushOffButton];
  [button_box addSubview: b];
  RELEASE(b);
  {
    NSUInteger i;
    CGFloat width = 88;
    for (i=0; i<[pref_buttons count]; i++)
      width = MAX(width,ceil([[[pref_buttons objectAtIndex:i] cell] cellSize].width)+16);
    [button_box setFrameSize: NSMakeSize(width*[pref_buttons count],88)];
    for (i=0; i<[pref_buttons count]; i++)
      [[pref_buttons objectAtIndex:i] setFrame: NSMakeRect(i*width,0,width,88)];
    /* Include the scroll-view border and window chrome, including when a
       narrower frame was restored from an earlier version's preferences. */
    NSWindow *window = [self window];
    NSRect frame = [window frame];
    NSSize minimum = [window minSize];
    CGFloat chrome = frame.size.width
      - [[button_box enclosingScrollView] contentSize].width;
    minimum.width = MAX(480,ceil(width*[pref_buttons count]+chrome));
    [window setMinSize: minimum];
    if (frame.size.width < minimum.width)
      {
        frame.size.width = minimum.width;
        [window setFrame: frame display: YES];
      }
  }

	if (!current)
		[self _displayBox: pb];
	else
		[[self window] autoSetupKeyViewChain];
}


/* well, it works */
-(BOOL) respondsToSelector: (SEL)s
{
	if ([super respondsToSelector: s])
		return YES;

	if (current)
		return [current respondsToSelector: s];
	return NO;
}

-(void) forwardInvocation: (NSInvocation *)i
{
	if (current)
		if ([current respondsToSelector: [i selector]])
		{
			[i invokeWithTarget: current];
			return;
		}
	[super forwardInvocation: i];
}

-(NSMethodSignature *) methodSignatureForSelector: (SEL)sel
{
	return [super methodSignatureForSelector: sel];
}

@end

