/* -*- mode: objc -*-

  Copyright (c) 2017 Riccardo Mottola <rm@gnu.org>

  This file is a part of Terminal.app.
  Optimized String classes for fast mutation.

  This program is free software; you can redistribute it and/or modify
  it under the terms of the GNU General Public License as published by
  the Free Software Foundation; version 2 of the License.

  This program is distributed in the hope that it will be useful,
  but WITHOUT ANY WARRANTY; without even the implied warranty of
  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
  GNU General Public License for more details.

  You should have received a copy of the GNU General Public License
  along with this program; if not, write to the Free Software
  Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA  02111-1307  USA
*/

#import <Foundation/Foundation.h>
#import <AppKit/NSFont.h>
#import <AppKit/NSColor.h>

/*
 Optimized NSString which represents a single unicode character.
 Exposed ivars allows mutation during View drawing.
*/

@interface SingleCharString : NSString
{
@public
  unichar       ch;
}

@end

/*
 Special NSDictionary for fast mutation of String Attributes
 through exposed ivars.
 */
@interface StringAttributesDict : NSDictionary
{
  NSArray *keys;
@public
  NSFont *font;
  NSColor *foregroundColor;
  NSColor *backgroundColor;
  NSParagraphStyle *paragraphStyle;
}
@end
