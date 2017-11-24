
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
