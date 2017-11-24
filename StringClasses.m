/*
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
#import <AppKit/NSAttributedString.h>
#import <StringClasses.h>

@implementation SingleCharString

- (id) initWithBytesNoCopy: (void *)c
                    length: (NSUInteger)l
                  encoding: (NSStringEncoding)encoding
              freeWhenDone: (BOOL)freeWhenDone
{
  if (2 == l && NSUnicodeStringEncoding == encoding)
    {
      ch = *((unichar*)c);
    }
  else
    {
      [self release];
      self = nil;
    }
  return self;
}

- (NSUInteger) length
{
  return 1;
}

- (unichar) characterAtIndex: (NSUInteger)index
{
  return ch;
}

@end

@implementation StringAttributesDict

- (id)init
{
  self = [super init];
  keys = [[NSArray alloc] initWithObjects:
			    NSFontAttributeName,
			  NSForegroundColorAttributeName,
			  NSBackgroundColorAttributeName,
			  NSParagraphStyleAttributeName,
			  nil];
  font = nil;
  foregroundColor = nil;
  backgroundColor = nil;
  paragraphStyle = [[NSParagraphStyle defaultParagraphStyle] retain];
  return self;
}

- (void)dealloc
{
  [keys release];
  [paragraphStyle release];
  [super dealloc];
}

- (NSArray *)allKeys
{
  return keys;
}

- (NSEnumerator *)keyEnumerator
{
  return [keys objectEnumerator];
}

- (NSUInteger)count
{
  return [keys count];
}

- (id) objectForKey:(id)aKey
{
  if (aKey == NSFontAttributeName)
    return font;
  if (aKey == NSForegroundColorAttributeName)
    return foregroundColor;
  if (aKey == NSBackgroundColorAttributeName)
    return backgroundColor;
  if (aKey == NSParagraphStyleAttributeName)
    return paragraphStyle;

  NSLog(@"asking for unknown key: %@", aKey);
  return nil;
}

@end
