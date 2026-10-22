/*
 * This file is part of Terminal.app.
 * Copyright (C) 2026 Terminal contributors.
 * This program is free software: you can redistribute it and/or modify it
 * under the terms of the GNU General Public License, version 3 or later.
 * This program is distributed WITHOUT ANY WARRANTY; without even the implied
 * warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
 * See <https://www.gnu.org/licenses/> for a copy of the license.
 */

#import <AppKit/AppKit.h>
#import "TerminalParser_VTerm.h"
@interface TerminalViewKeyboardPrefs : NSObject

+(BOOL) commandAsMeta;
+(BOOL) altIsNotMeta;
+(BOOL) doubleEscape;

@end
#include <string.h>

/* Keyboard preferences are fixed here so tests do not change user defaults. */
@implementation TerminalViewKeyboardPrefs

+(BOOL) commandAsMeta { return NO; }

+(BOOL) altIsNotMeta { return NO; }

+(BOOL) doubleEscape { return NO; }

@end

@interface TestScreen : NSObject <TerminalScreen>
{
@public
  screen_char_t cells[40][100];
  NSMutableData *output;
  NSMutableArray *history;
  NSString *title;
  int x,y;
  BOOL visible;
}

@end

@implementation TestScreen

-(id) init
{
  if ((self=[super init]))
    {
      output=[[NSMutableData alloc] init];
      history=[[NSMutableArray alloc] init];
    }
  return self;
}

-(void) dealloc
{
  DESTROY(output); DESTROY(history); DESTROY(title);
  DEALLOC;
}

-(void) ts_sendCString: (const char *)s
{
  [self ts_sendCString:s length:strlen(s)];
}

-(void) ts_sendCString: (const char *)s length: (int)n
{
  [output appendBytes:s length:n];
}

-(void) ts_goto: (int)xx : (int)yy
{
  x=xx; y=yy;
}

-(void) ts_putChar: (screen_char_t)c count: (int)n at: (int)xx : (int)yy
{
  while (n--) cells[yy][xx++]=c;
}

-(void) ts_putChar: (screen_char_t)c count: (int)n offset: (int)o
{
  [self doesNotRecognizeSelector:_cmd];
}

-(void) ts_scrollUp: (int)t : (int)b rows: (int)n save: (BOOL)s
{
  [self doesNotRecognizeSelector:_cmd];
}

-(void) ts_scrollDown: (int)t : (int)b rows: (int)n
{
  [self doesNotRecognizeSelector:_cmd];
}

-(void) ts_shiftRow: (int)y at: (int)x delta: (int)d
{
  [self doesNotRecognizeSelector:_cmd];
}

-(screen_char_t) ts_getCharAt: (int)xx : (int)yy
{
  return cells[yy][xx];
}

-(void) ts_setTitle: (NSString *)text type: (int)type
{
  ASSIGN(title,text);
}

-(void) ts_setCursorVisible: (BOOL)v
{
  visible=v;
}

-(void) ts_clearScrollback
{
  [history removeAllObjects];
}

-(void) ts_appendScrollback: (const screen_char_t *)line count: (int)n
{
  [history addObject:[NSData dataWithBytes:line length:n*sizeof(*line)]];
}

-(BOOL) ts_popScrollback: (screen_char_t *)line count: (int)n
{
  NSData *data=[history lastObject];
  if (!data) return NO;
  memset(line,0,n*sizeof(*line));
  memcpy(line,[data bytes],MIN([data length],n*sizeof(*line)));
  [history removeLastObject];
  return YES;
}

-(BOOL) useMultiCellGlyphs { return YES; }

-(int) relativeWidthOfCharacter: (unichar)c { return 1; }

@end

static int failures;
static void check(BOOL ok, const char *name)
{
  printf("%s: %s\n",ok ? "PASS" : "FAIL",name);
  if (!ok) failures++;
}

static void feed(TerminalParser_VTerm *p, const char *s)
{
  [p processBytes:s length:strlen(s)];
}

static BOOL sent(TestScreen *s, const char *text)
{
  return [s->output length]==strlen(text) &&
    !memcmp([s->output bytes],text,strlen(text));
}

static void key(TerminalParser_VTerm *p, unichar c, NSUInteger flags)
{
  NSString *s=[NSString stringWithCharacters:&c length:1];
  NSEvent *event=[NSEvent keyEventWithType:NSKeyDown location:NSZeroPoint
    modifierFlags:flags timestamp:0 windowNumber:0 context:nil
    characters:s charactersIgnoringModifiers:s isARepeat:NO keyCode:0];
  [p handleKeyEvent:event];
}

int main(void)
{
  NSAutoreleasePool *pool=[[NSAutoreleasePool alloc] init];
  TestScreen *s=[[TestScreen alloc] init];
  TerminalParser_VTerm *p=[[TerminalParser_VTerm alloc]
    initWithTerminalScreen:s width:10 height:3];
  feed(p,"abc\033[2;3HZ");
  check(s->cells[0][0].ch=='a' && s->cells[1][2].ch=='Z',"text and cursor addressing");
  feed(p,"\033[31;1mR\033[0m");
  check((s->cells[1][3].color&15)==4 && (s->cells[1][3].attr&3)==2,"SGR color and bold");
  feed(p,"\033[?1049hALT\033[?1049l");
  check(s->cells[0][0].ch=='a' && s->cells[1][2].ch=='Z',"alternate screen restores primary");
  feed(p,"\033[?25l"); check(!s->visible,"hide cursor");
  feed(p,"\033[?25h"); check(s->visible,"show cursor");
  feed(p,"\033]2;split "); feed(p,"title\033\\");
  check([s->title isEqualToString:@"split title"],"fragmented OSC title");
  feed(p,"\033[H\xc3"); feed(p,"\xa9");
  check(s->cells[0][0].ch==0xe9,"fragmented UTF-8");
  feed(p,"\033[H\xe7\x95\x8c");
  check(s->cells[0][0].ch==0x754c && s->cells[0][1].ch==MULTI_CELL_GLYPH,"wide character continuation");
  [s->output setLength:0]; feed(p,"\033[2;3H\033[6n");
  check(sent(s,"\033[2;3R"),"cursor position reply");
  [s->output setLength:0]; key(p,NSUpArrowFunctionKey,0);
  check(sent(s,"\033[A"),"normal cursor key");
  [s->output setLength:0]; feed(p,"\033[?1h"); key(p,NSUpArrowFunctionKey,0);
  check(sent(s,"\033OA"),"application cursor key");
  [s->output setLength:0]; key(p,'c',NSControlKeyMask);
  check(sent(s,"\003"),"control key");
  [s->output setLength:0]; key(p,'x',NSAlternateKeyMask);
  check(sent(s,"\033x"),"meta key");
  [s->output setLength:0]; feed(p,"\033[?2004h"); [p sendString:@"a\nb"];
  check(sent(s,"\033[200~a\rb\033[201~"),"bracketed paste");
  feed(p,"\033c1\r\n2\r\n3\r\n4");
  check([s->history count]==1 && s->cells[0][0].ch=='2',"scrolling saves history");
  feed(p,"\033[?1049hA\r\nB\r\nC\r\nD\033[?1049l");
  check([s->history count]==1,"alternate scrolling does not pollute history");
  [p setTerminalScreenWidth:10 height:4];
  check([s->history count]==0 && s->cells[0][0].ch=='1' && s->cells[3][0].ch=='4',"growing restores history");
  [p setTerminalScreenWidth:10 height:2];
  check([s->history count]==2 && s->cells[0][0].ch=='3',"shrinking saves displaced lines once");
  feed(p,"\033[3J"); check([s->history count]==0,"erase scrollback");
  feed(p,"\033c\033[38;2;12;34;56me\xcc\x81\r\n2\r\n3");
  [p setTerminalScreenWidth:10 height:3];
  check(s->cells[0][0].originalCell.chars[1]==0x301 &&
        s->cells[0][0].originalCell.fg.rgb.red==12,
        "history retains combining characters and true color");

  feed(p,"\033c\033[2;4H\033[s\033[H\033[uX");
  check(s->cells[1][3].ch=='X',"CSI s/u restores bpytop cursor position");
  feed(p,"\033[2;5H\033[s");
  feed(p,"\033[H\033["); feed(p,"uY");
  check(s->cells[1][4].ch=='Y',"fragmented cursor restore");
  feed(p,"\033c\033[?69h\033[3;8s\033[?6hZ");
  check(s->cells[0][2].ch=='Z',"CSI s still sets enabled left/right margins");
  feed(p,"\033c\033[38;2;12;34;56mT\033[48;5;196m ");
  check(s->cells[0][0].foreground.rgb.red==12 &&
        s->cells[0][0].foreground.rgb.green==34 &&
        s->cells[0][0].foreground.rgb.blue==56 &&
        s->cells[0][1].background.rgb.red==255 &&
        s->cells[0][1].background.rgb.green==0,
        "display retains exact truecolor and resolves indexed colors");

  RELEASE(p); RELEASE(s); RELEASE(pool);
  return failures ? 1 : 0;
}

