/*
 * This file is part of Terminal.app.
 * Copyright (C) 2026 Terminal contributors.
 * This program is free software: you can redistribute it and/or modify it
 * under the terms of the GNU General Public License, version 3 or later.
 * This program is distributed WITHOUT ANY WARRANTY; without even the implied
 * warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
 * See <https://www.gnu.org/licenses/> for a copy of the license.
 */

#import "TerminalParser_VTerm.h"
#import "TerminalViewPrefs.h"
#import <AppKit/NSGraphics.h>
#import <AppKit/NSText.h>
#include <limits.h>
#include <string.h>

@interface TerminalParser_VTerm (Callbacks)

-(int) damage: (VTermRect)rect;
-(int) cursor: (VTermPos)pos visible: (int)visible;
-(int) property: (VTermProp)prop value: (VTermValue *)value;
-(int) push: (int)cols cells: (const VTermScreenCell *)cells;
-(int) pop: (int)cols cells: (VTermScreenCell *)cells;
-(void) output: (const char *)bytes length: (size_t)length;
-(void) clearHistory;

@end

static int damage(VTermRect r, void *u)
{
  return [(TerminalParser_VTerm *)u damage: r];
}

static int cursor(VTermPos p, VTermPos old, int visible, void *u)
{
  return [(TerminalParser_VTerm *)u cursor: p visible: visible];
}

static int property(VTermProp p, VTermValue *v, void *u)
{
  return [(TerminalParser_VTerm *)u property: p value: v];
}

static int bell(void *u)
{
  NSBeep();
  return 1;
}

static int push(int cols, const VTermScreenCell *cells, void *u)
{
  return [(TerminalParser_VTerm *)u push: cols cells: cells];
}

static int pop(int cols, VTermScreenCell *cells, void *u)
{
  return [(TerminalParser_VTerm *)u pop: cols cells: cells];
}

static int clear(void *u)
{
  [(TerminalParser_VTerm *)u clearHistory];
  return 1;
}

static void output(const char *bytes, size_t length, void *u)
{
  [(TerminalParser_VTerm *)u output: bytes length: length];
}

static const VTermScreenCallbacks callbacks = {
  damage, NULL, cursor, property, bell, NULL, push, pop, clear
};

/* Retain the legacy packed palette field for compatibility. Rendering uses
   the separate resolved RGB colors, not this approximation. */
static int paletteIndex(VTermScreen *screen, VTermColor color, int fallback)
{
  int i, best=0, distance=INT_MAX;
  static const unsigned char rgb[16][3] = {
    {0,0,0},{170,0,0},{0,170,0},{170,85,0},
    {0,0,170},{170,0,170},{0,170,170},{170,170,170},
    {85,85,85},{255,85,85},{85,255,85},{255,255,85},
    {85,85,255},{255,85,255},{85,255,255},{255,255,255}
  };
  if (VTERM_COLOR_IS_DEFAULT_FG(&color) || VTERM_COLOR_IS_DEFAULT_BG(&color))
    return fallback;
  if (VTERM_COLOR_IS_INDEXED(&color) && color.indexed.idx < 16)
    return color.indexed.idx;
  vterm_screen_convert_color_to_rgb(screen, &color);
  for (i=0; i<16; i++)
    {
      int r=color.rgb.red-rgb[i][0], g=color.rgb.green-rgb[i][1];
      int b=color.rgb.blue-rgb[i][2], d=r*r+g*g+b*b;
      if (d<distance) { distance=d; best=i; }
    }
  return best;
}

static screen_char_t displayCell(VTermScreen *screen, const VTermScreenCell *cell)
{
  screen_char_t result;
  uint32_t c=cell->chars[0];
  memset(&result,0,sizeof(result));
  result.originalCell=*cell;
  result.foreground=cell->fg;
  result.background=cell->bg;
  vterm_screen_convert_color_to_rgb(screen,&result.foreground);
  vterm_screen_convert_color_to_rgb(screen,&result.background);
  result.ch=c == (uint32_t)-1 ? MULTI_CELL_GLYPH :
    (c>0xffff ? 0xfffd : (c ? c : ' '));
  if (cell->attrs.conceal) result.ch=' ';
  {
    int fg=paletteIndex(screen,cell->fg,7), bg=paletteIndex(screen,cell->bg,0);
    /* Terminal's historical display palette uses BGR bit order. */
    fg=(fg&10)|((fg&1)<<2)|((fg&4)>>2);
    bg=(bg&10)|((bg&1)<<2)|((bg&4)>>2);
    result.color=fg|(bg<<4);
  }
  result.attr=(cell->attrs.bold ? 2 : 1) |
    (cell->attrs.underline ? 4 : 0) |
    (cell->attrs.reverse ? 8 : 0) | (cell->attrs.blink ? 16 : 0);
  return result;
}

@implementation TerminalParser_VTerm

- initWithTerminalScreen: (id<TerminalScreen>)aScreen width: (int)w height: (int)h
{
  if (!(self=[super init])) return nil;
  ts=aScreen;
  width=MAX(1,w); height=MAX(1,h);
  terminal=vterm_new(height,width);
  if (!terminal) { RELEASE(self); return nil; }
  title=[[NSMutableData alloc] init];
  iconTitle=[[NSMutableData alloc] init];
  vterm_set_utf8(terminal,1);
  vterm_output_set_callback(terminal,output,self);
  screen=vterm_obtain_screen(terminal);
  vterm_screen_set_callbacks(screen,&callbacks,self);
  vterm_screen_enable_altscreen(screen,1);
  vterm_screen_set_damage_merge(screen,VTERM_DAMAGE_SCREEN);
  vterm_screen_reset(screen,1);
  vterm_screen_flush_damage(screen);
  return self;
}

-(void) dealloc
{
  if (terminal) vterm_free(terminal);
  DESTROY(title);
  DESTROY(iconTitle);
  DEALLOC;
}

-(int) damage: (VTermRect)rect
{
  VTermPos p;
  VTermScreenCell cell;
  for (p.row=MAX(0,rect.start_row); p.row<MIN(height,rect.end_row); p.row++)
    for (p.col=MAX(0,rect.start_col); p.col<MIN(width,rect.end_col); p.col++)
      if (vterm_screen_get_cell(screen,p,&cell))
        [ts ts_putChar: displayCell(screen,&cell) count: 1 at: p.col : p.row];
  return 1;
}

-(int) cursor: (VTermPos)pos visible: (int)visible
{
  [ts ts_goto: pos.col : pos.row];
  [ts ts_setCursorVisible: visible != 0];
  return 1;
}

-(int) property: (VTermProp)prop value: (VTermValue *)value
{
  if (prop==VTERM_PROP_CURSORVISIBLE)
    [ts ts_setCursorVisible: value->boolean != 0];
  else if (prop==VTERM_PROP_TITLE || prop==VTERM_PROP_ICONNAME)
    {
      NSMutableData *data=prop==VTERM_PROP_TITLE ? title : iconTitle;
      if (value->string.initial) [data setLength: 0];
      /* Bound untrusted OSC strings, including streams without a terminator. */
      if ([data length]+value->string.len <= 65536)
        [data appendBytes: value->string.str length: value->string.len];
      if (value->string.final)
        {
          NSString *text=[[NSString alloc] initWithData: data
                                             encoding: NSUTF8StringEncoding];
          if (text) [ts ts_setTitle: text type: prop==VTERM_PROP_TITLE ? 2 : 1];
          RELEASE(text);
          [data setLength: 0];
        }
    }
  return 1;
}

-(int) push: (int)cols cells: (const VTermScreenCell *)cells
{
  screen_char_t *line=calloc(cols,sizeof(*line));
  int i;
  if (!line) return 0;
  for (i=0; i<cols; i++) line[i]=displayCell(screen,&cells[i]);
  [ts ts_appendScrollback: line count: cols];
  free(line);
  return 1;
}

-(int) pop: (int)cols cells: (VTermScreenCell *)cells
{
  screen_char_t *line=calloc(cols,sizeof(*line));
  int i;
  if (!line) return 0;
  if (![ts ts_popScrollback: line count: cols]) { free(line); return 0; }
  memset(cells,0,cols*sizeof(*cells));
  for (i=0; i<cols; i++)
    {
      cells[i]=line[i].originalCell;
      if (!cells[i].width)
        {
          cells[i].width=1;
          vterm_state_get_default_colors(vterm_obtain_state(terminal),
                                        &cells[i].fg,&cells[i].bg);
        }
    }
  free(line);
  return 1;
}

-(void) clearHistory
{
  [ts ts_clearScrollback];
}

-(void) output: (const char *)bytes length: (size_t)length
{
  [ts ts_sendCString: bytes length: (int)length];
}

-(void) processByte: (unsigned char)c
{
  [self processBytes: (const char *)&c length: 1];
}

-(void) processBytes: (const char *)bytes length: (NSUInteger)length
{
  vterm_input_write(terminal,bytes,length);
  vterm_screen_flush_damage(screen);
}

-(void) setTerminalScreenWidth: (int)w height: (int)h
{
  width=MAX(1,w); height=MAX(1,h);
  vterm_set_size(terminal,height,width);
  vterm_screen_flush_damage(screen);
  /* A resize may leave unchanged cells outside the damage rectangle. */
  { VTermRect rect={0,height,0,width}; [self damage: rect]; }
}

-(void) sendString: (NSString *)text
{
  NSData *data=[[text stringByReplacingOccurrencesOfString: @"\n" withString: @"\r"]
    dataUsingEncoding: NSUTF8StringEncoding];
  vterm_keyboard_start_paste(terminal);
  [self output: [data bytes] length: [data length]];
  vterm_keyboard_end_paste(terminal);
}

-(void) handleKeyEvent: (NSEvent *)event
{
  NSString *characters=[event characters];
  NSString *plain=[event charactersIgnoringModifiers];
  NSUInteger flags=[event modifierFlags], i;
  BOOL commandMeta=[TerminalViewKeyboardPrefs commandAsMeta];
  BOOL meta=(commandMeta && (flags&NSCommandKeyMask)) ||
    (!commandMeta && ![TerminalViewKeyboardPrefs altIsNotMeta] &&
     (flags&NSAlternateKeyMask));
  VTermModifier mods=VTERM_MOD_NONE;
  VTermKey key=VTERM_KEY_NONE;
  unichar c;
  if ([plain length]>1 && [plain characterAtIndex:0]==NSHelpFunctionKey)
    plain=[plain substringFromIndex:1];
  if ([characters length]>1 && [characters characterAtIndex:0]==NSHelpFunctionKey)
    characters=[characters substringFromIndex:1];
  if (![plain length]) return;
  c=[plain characterAtIndex:0];
  if (flags&NSShiftKeyMask) mods|=VTERM_MOD_SHIFT;
  if (flags&NSControlKeyMask) mods|=VTERM_MOD_CTRL;
  if (meta) mods|=VTERM_MOD_ALT;
  switch (c)
    {
    case '\r':
    case '\n':
      key = VTERM_KEY_ENTER;
      break;
    case '\t':
    case NSBackTabCharacter:
      key = VTERM_KEY_TAB;
      break;
    case 0x7f:
    case '\b':
      key = VTERM_KEY_BACKSPACE;
      break;
    case 0x1b:
      key = VTERM_KEY_ESCAPE;
      break;
    case NSUpArrowFunctionKey:
      key = VTERM_KEY_UP;
      break;
    case NSDownArrowFunctionKey:
      key = VTERM_KEY_DOWN;
      break;
    case NSLeftArrowFunctionKey:
      key = VTERM_KEY_LEFT;
      break;
    case NSRightArrowFunctionKey:
      key = VTERM_KEY_RIGHT;
      break;
    case NSHomeFunctionKey:
      key = VTERM_KEY_HOME;
      break;
    case NSEndFunctionKey:
      key = VTERM_KEY_END;
      break;
    case NSInsertFunctionKey:
      key = VTERM_KEY_INS;
      break;
    case NSDeleteFunctionKey:
      key = VTERM_KEY_DEL;
      break;
    case NSPageUpFunctionKey:
      key = VTERM_KEY_PAGEUP;
      break;
    case NSPageDownFunctionKey:
      key = VTERM_KEY_PAGEDOWN;
      break;
    }
  if (c >= NSF1FunctionKey && c <= NSF35FunctionKey)
    key = VTERM_KEY_FUNCTION (c - NSF1FunctionKey + 1);
  if ([event modifierFlags] & NSNumericPadKeyMask)
    {
      if (c >= '0' && c <= '9')
        key = VTERM_KEY_KP_0 + c - '0';
      else if (c == '\r' || c == '\n' || c == NSEnterCharacter)
        key = VTERM_KEY_KP_ENTER;
      else if (c == '+')
        key = VTERM_KEY_KP_PLUS;
      else if (c == '-')
        key = VTERM_KEY_KP_MINUS;
      else if (c == '*')
        key = VTERM_KEY_KP_MULT;
      else if (c == '/')
        key = VTERM_KEY_KP_DIVIDE;
      else if (c == '.')
        key = VTERM_KEY_KP_PERIOD;
      else if (c == ',')
        key = VTERM_KEY_KP_COMMA;
      else if (c == '=')
        key = VTERM_KEY_KP_EQUAL;
    }
  if (c==NSEnterCharacter) key=VTERM_KEY_ENTER;
  if (c==NSBackTabCharacter) mods|=VTERM_MOD_SHIFT;
  if (key)
    {
      vterm_keyboard_key(terminal,key,mods);
      if (key==VTERM_KEY_ESCAPE && [TerminalViewKeyboardPrefs doubleEscape])
        vterm_keyboard_key(terminal,key,mods);
      return;
    }
  if (mods&(VTERM_MOD_CTRL|VTERM_MOD_ALT)) characters=plain;
  /* Shift has already been applied to the text by the input method. */
  mods &= ~VTERM_MOD_SHIFT;
  for (i=0; i<[characters length]; i++)
    {
      uint32_t code=[characters characterAtIndex:i];
      if (code>=0xd800 && code<=0xdbff && i+1<[characters length])
        {
          unichar tail=[characters characterAtIndex:i+1];
          if (tail>=0xdc00 && tail<=0xdfff)
            { code=0x10000+((code-0xd800)<<10)+tail-0xdc00; i++; }
        }
      vterm_keyboard_unichar(terminal,code,mods);
    }
}

@end
