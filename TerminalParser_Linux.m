/*
copyright 2002, 2003 Alexander Malmberg <alexander@malmberg.org>
2009-2011 GAP Project

This file is a part of Terminal.app. Terminal.app is free software; you
can redistribute it and/or modify it under the terms of the GNU General
Public License as published by the Free Software Foundation; version 2
of the License. See COPYING or main.m for more information.
*/
/*
lots borrowed from linux/drivers/char/console.c, GNU GPL:ed
*/
/*
 *  linux/drivers/char/console.c
 *
 *  Copyright (C) 1991, 1992  Linus Torvalds
 */


#import <Foundation/NSString.h>
#import <Foundation/NSDebug.h>
#import <Foundation/NSNotification.h>
#import <AppKit/NSGraphics.h>

#include <netinet/in.h>

/* TODO */
#import "TerminalViewPrefs.h"
#import <AppKit/NSEvent.h>

#import "TerminalParser_Linux.h"

#import "TerminalParser_LinuxPrefs.h"


#include "charmaps.h"

#define set_translate(charset,foo) _set_translate(charset)
static const unichar *_set_translate(int charset)
{
	if (charset<0 || charset>=4)
		return translate_maps[0];
	return translate_maps[charset];
}


@interface TerminalParser_Linux (private)

#define csi_J(foo,vpar) [self _csi_J: vpar]
#define csi_K(foo,vpar) [self _csi_K: vpar]
#define csi_L(foo,vpar) [self _csi_L: vpar]
#define csi_M(foo,vpar) [self _csi_M: vpar]
#define csi_P(foo,vpar) [self _csi_P: vpar]
#define csi_X(foo,vpar) [self _csi_X: vpar]
#define csi_at(foo,vpar) [self _csi_at: vpar]
#define csi_m(foo) [self _csi_m]

-(void) _csi_J: (int)vpar;
-(void) _csi_K: (int)vpar;
-(void) _csi_L: (unsigned int)vpar;
-(void) _csi_M: (unsigned int)vpar;
-(void) _csi_P: (unsigned int)vpar;
-(void) _csi_X: (int)vpar;
-(void) _csi_at: (unsigned int)vpar;
-(void) _csi_m;

-(void) _carriageReturn;
-(void) _lineFeed;
-(void) _reverseIndex;
-(void) _clearDisplay;
-(void) _putScreenChar: (screen_char_t)ch;
-(void) _putUnicodeCharacter: (unichar)uc;
-(void) _tabForward: (int)count;
-(void) _tabBackward: (int)count;
-(void) _screenAlignmentTest;
-(void) _default_attr;
-(void) _update_attr;

@end


#define SCREEN(x,y) ((x)+(y)*width)

static NSString *TerminalStringByDroppingKeyEquivalentPrefix(NSString *s)
{
	if ([s length]>1 && [s characterAtIndex: 0]==NSHelpFunctionKey)
		return [s substringFromIndex: 1];
	return s;
}


@implementation TerminalParser_Linux


#define gotoxy(foo,new_x,new_y) do { \
	int min_y, max_y; \
 \
	if (new_x < 0) \
		x = 0; \
	else \
		if (new_x >= width) \
			x = width - 1; \
		else \
			x = new_x; \
	if (decom) { \
		min_y = top; \
		max_y = bottom; \
	} else { \
		min_y = 0; \
		max_y = height; \
	} \
	if (new_y < min_y) \
		y = min_y; \
	else if (new_y >= max_y) \
		y = max_y - 1; \
	else \
		y = new_y; \
	[ts ts_goto: x:y]; \
} while (0)

#define gotoxay(foo,nx,ny) gotoxy(foo,nx,decom?top+ny:ny)


#define save_cur(foo) do { \
	saved_x		= x; \
	saved_y		= y; \
	s_intensity	= intensity; \
	s_underline	= underline; \
	s_blink		= blink; \
	s_reverse	= reverse; \
	s_charset	= charset; \
	s_color		= color; \
	saved_G0	= G0_charset; \
	saved_G1	= G1_charset; \
} while (0)

#define restore_cur(foo) do { \
	gotoxy(currcons,saved_x,saved_y); \
	intensity	= s_intensity; \
	underline	= s_underline; \
	blink		= s_blink; \
	reverse		= s_reverse; \
	charset		= s_charset; \
	color		= s_color; \
	G0_charset	= saved_G0; \
	G1_charset	= saved_G1; \
	translate	= set_translate(charset ? G1_charset : G0_charset,currcons); \
} while (0)


-(void) _reset_terminal
{
	top		= 0;
	bottom		= height;
	vc_state	= ESnormal;
	ques		= 0;
	csi_private	= 0;
	csi_intermediate = 0;

	translate	= set_translate(LAT1_MAP,currcons);
	G0_charset	= LAT1_MAP;
	G1_charset	= GRAF_MAP;

	charset		= 0;
//	report_mouse	= 0;
	utf             = 0;
	utf_count       = 0;
	have_last_char	= 0;

	disp_ctrl	= 0;
	toggle_meta	= 0;

	decscnm		= 0;
	decom		= 0;
	decawm		= 1;
	deccm		= 1;
	decim		= 0;
	[ts ts_setCursorVisible: YES];

#if 0
	set_kbd(decarm);
	clr_kbd(decckm);
	clr_kbd(kbdapplic);
	clr_kbd(lnm);
	kbd_table[currcons].lockstate = 0;
	kbd_table[currcons].slockstate = 0;
	kbd_table[currcons].ledmode = LED_SHOW_FLAGS;
	kbd_table[currcons].ledflagstate = kbd_table[currcons].default_ledflagstate;
	set_leds();

	cursor_type = CUR_DEFAULT;
	complement_mask = s_complement_mask;
#endif

	[self _default_attr];
	[self _update_attr];

	tab_stop[0]= 0x01010100;
	tab_stop[1]=tab_stop[2]=tab_stop[3]=tab_stop[4]=
		tab_stop[5]=tab_stop[6]=tab_stop[7]=0x01010101;

	gotoxy(currcons,0,0);
	save_cur(currcons);
	[self _csi_J: 2];
}


-(void) _csi_J: (int) vpar
{
	unsigned int count;
	int start;

	switch (vpar) {
		case 0:	/* erase from cursor to end of display */
			count = width*height-(x+y*width);
			start = SCREEN(x,y);
			break;
		case 1:	/* erase from start to cursor */
			count = x+y*width+1;
			start = SCREEN(0,0);
			break;
		case 2: /* erase whole display */
			count = width*height;
			start = SCREEN(0,0);
			break;
		case 3: /* erase scrollback */
			[ts ts_clearScrollback];
			return;
		default:
			return;
	}
	[ts ts_putChar: video_erase_char  count: count  offset: start];
}


-(void) _csi_K: (int)vpar
{
	unsigned int count;
	int start;

	switch (vpar) {
		case 0:	/* erase from cursor to end of line */
			count = width-x;
			start = SCREEN(x,y);
			break;
		case 1:	/* erase from start of line to cursor */
			count = x+1;
			start = SCREEN(0,y);
			break;
		case 2: /* erase whole line */
			count = width;
			start = SCREEN(0,y);
			break;
		default:
			return;
	}
	[ts ts_putChar: video_erase_char  count: count  offset: start];
}

-(void) _csi_X: (int)vpar /* erase the following vpar positions */
{ /* not vt100? */
	int count;

	if (!vpar)
		vpar++;
	count = (vpar > width-x) ? (width-x) : vpar;

	[ts ts_putChar: video_erase_char  count: count  offset: SCREEN(x,y)];
}


-(void) _default_attr
{
	intensity = 1;
	underline = 0;
	reverse = 0;
	blink = 0;
	color = def_color;
}

-(void) _update_attr
{
	video_erase_char.color=color;
	video_erase_char.attr=(intensity)|(underline<<2)|(reverse<<3)|(blink<<4);
}


static unsigned char color_table[] = { 0, 4, 2, 6, 1, 5, 3, 7,
				       8,12,10,14, 9,13,11,15 };

static unsigned char
_colorFromRGB(int red, int green, int blue)
{
	static const int ansi_rgb[16][3] = {
		{  0,   0,   0}, {170,   0,   0},
		{  0, 170,   0}, {170,  85,   0},
		{  0,   0, 170}, {170,   0, 170},
		{  0, 170, 170}, {170, 170, 170},
		{ 85,  85,  85}, {255,  85,  85},
		{ 85, 255,  85}, {255, 255,  85},
		{ 85,  85, 255}, {255,  85, 255},
		{ 85, 255, 255}, {255, 255, 255}
	};
	int i, best = 0, best_dist = 0x7fffffff;

	if (red < 0) red = 0;
	if (green < 0) green = 0;
	if (blue < 0) blue = 0;
	if (red > 255) red = 255;
	if (green > 255) green = 255;
	if (blue > 255) blue = 255;

	for (i = 0; i < 16; i++)
	{
		int dr = red - ansi_rgb[i][0];
		int dg = green - ansi_rgb[i][1];
		int db = blue - ansi_rgb[i][2];
		int dist = dr * dr + dg * dg + db * db;

		if (dist < best_dist)
		{
			best = i;
			best_dist = dist;
		}
	}

	return color_table[best];
}

static unsigned char
_colorFrom256(int index)
{
	static const int cube[] = { 0, 95, 135, 175, 215, 255 };

	if (index < 0)
		index = 0;
	else if (index > 255)
		index = 255;

	if (index < 16)
		return color_table[index];
	if (index < 232)
	{
		index -= 16;
		return _colorFromRGB(cube[index / 36],
				     cube[(index / 6) % 6],
				     cube[index % 6]);
	}

	index = 8 + (index - 232) * 10;
	return _colorFromRGB(index, index, index);
}

-(void) _csi_m
{
	int i;

	for (i=0;i<=npar;i++)
		switch (par[i]) {
			case 0:	/* all attributes off */
				[self _default_attr];
				break;
			case 1:
				intensity = 2;
				break;
			case 2:
				intensity = 0;
				break;
			case 4:
				underline = 1;
				break;
			case 5:
				blink = 1;
				break;
			case 7:
				reverse = 1;
				break;
			case 10: /* ANSI X3.64-1979 (SCO-ish?)
				  * Select primary font, don't display
				  * control chars if defined, don't set
				  * bit 8 on output.
				  */
				translate = set_translate(charset == 0
						? G0_charset
						: G1_charset,currcons);
				disp_ctrl = 0;
				toggle_meta = 0;
				break;
			case 11: /* ANSI X3.64-1979 (SCO-ish?)
				  * Select first alternate font, lets
				  * chars < 32 be displayed as ROM chars.
				  */
				translate = set_translate(IBMPC_MAP,currcons);
				disp_ctrl = 1;
				toggle_meta = 0;
				break;
			case 12: /* ANSI X3.64-1979 (SCO-ish?)
				  * Select second alternate font, toggle
				  * high bit before displaying as ROM char.
				  */
				translate = set_translate(IBMPC_MAP,currcons);
				disp_ctrl = 1;
				toggle_meta = 1;
				break;
			case 21:
			case 22:
				intensity = 1;
				break;
			case 24:
				underline = 0;
				break;
			case 25:
				blink = 0;
				break;
			case 27:
				reverse = 0;
				break;
			case 90: case 91: case 92: case 93:
			case 94: case 95: case 96: case 97:
				color = color_table[par[i]-90+8]
					| background;
				break;
			case 100: case 101: case 102: case 103:
			case 104: case 105: case 106: case 107:
				color = (color_table[par[i]-100+8]<<4)
					| foreground;
				break;
			case 38:
				if (i+2<=npar && par[i+1]==5)
				{
					color = _colorFrom256(par[i+2])
						| background;
					i += 2;
				}
				else if (i+4<=npar && par[i+1]==2)
				{
					color = _colorFromRGB(par[i+2],
							      par[i+3],
							      par[i+4])
						| background;
					i += 4;
				}
				else if (i+1<=npar &&
					 (par[i+1]==2 || par[i+1]==5))
				{
					i = npar;
				}
				else
				{
					color = (def_color & 0x0f) | background;
					underline = 1;
				}
				break;
			case 39:
				color = (def_color & 0x0f) | background;
				break;
			case 49:
				color = (def_color & 0xf0) | foreground;
				break;
			case 48:
				if (i+2<=npar && par[i+1]==5)
				{
					color = (_colorFrom256(par[i+2])<<4)
						| foreground;
					i += 2;
				}
				else if (i+4<=npar && par[i+1]==2)
				{
					color = (_colorFromRGB(par[i+2],
							       par[i+3],
							       par[i+4])<<4)
						| foreground;
					i += 4;
				}
				else if (i+1<=npar &&
					 (par[i+1]==2 || par[i+1]==5))
				{
					i = npar;
				}
				break;
			default:
				if (par[i] >= 30 && par[i] <= 37)
					color = color_table[par[i]-30]
						| background;
				else if (par[i] >= 40 && par[i] <= 47)
					color = (color_table[par[i]-40]<<4)
						| foreground;
				break;
		}

	[self _update_attr];
}


#define scrup(foo,t,b,nr,indirect_scroll) do { \
	int scrup_nr=nr; \
 \
	if (t+scrup_nr >= b) \
		scrup_nr = b - t - 1; \
	if (b > height || t >= b || scrup_nr < 1) \
		return; \
	[ts ts_scrollUp: t:b  rows: scrup_nr  save: indirect_scroll]; \
	[ts ts_putChar: video_erase_char  count: width*scrup_nr  offset: width*(b-scrup_nr)]; \
} while (0)

#define scrdown(foo,t,b,nr) do { \
	unsigned int step; \
	int scrdown_nr=nr; \
 \
	if (t+scrdown_nr >= b) \
		scrdown_nr = b - t - 1; \
	if (b > height || t >= b || scrdown_nr < 1) \
		return; \
	step = width * scrdown_nr; \
	[ts ts_scrollDown: t:b  rows: scrdown_nr]; \
	[ts ts_putChar: video_erase_char  count: step  offset: t*width]; \
} while (0)

-(void) _carriageReturn
{
	x=0;
	[ts ts_goto: x:y];
}

-(void) _lineFeed
{
	if (y+1==bottom)
	{
		scrup(foo,top,bottom,1,(top==0 && bottom==height)?YES:NO);
	}
	else if (y<height-1)
	{
		y++;
		[ts ts_goto: x:y];
	}
}

-(void) _reverseIndex
{
	if (y==top)
	{
		scrdown(foo,top,bottom,1);
	}
	else if (y>0)
	{
		y--;
		[ts ts_goto: x:y];
	}
}

-(void) _clearDisplay
{
	[self _csi_J: 2];
	gotoxy(currcons,0,0);
}

-(void) _putScreenChar: (screen_char_t)ch
{
	int char_width;

	if (x>=width && decawm)
	{
		[self _carriageReturn];
		[self _lineFeed];
	}
	char_width=[ts relativeWidthOfCharacter: ch.ch];
	if (char_width<1)
		char_width=1;
	if (decim)
		[ts ts_shiftRow: y  at: x  delta: char_width];
	[ts ts_putChar: ch  count: 1  at: x:y];
	last_char=ch;
	have_last_char=1;
	if (x<width)
	{
		x++;
		char_width--;
		if (char_width+x>width)
			char_width=width-x;
		if (char_width>0)
		{
			ch.ch=MULTI_CELL_GLYPH;
			[ts ts_putChar: ch  count: char_width  at: x:y];
			x+=char_width;
		}
		[ts ts_goto: x:y];
	}
}

-(void) _putUnicodeCharacter: (unichar)uc
{
	screen_char_t ch;

	ch.color=color;
	ch.attr=(intensity)|(underline<<2)|(reverse<<3)|(blink<<4);
	ch.ch=uc;
	[self _putScreenChar: ch];
}

-(void) _tabForward: (int)count
{
	if (count<1)
		count=1;
	while (count-- > 0 && x < width - 1)
	{
		do
		{
			x++;
		} while (x < width - 1 &&
		         !(tab_stop[x >> 5] & (1 << (x & 31))));
	}
	[ts ts_goto: x:y];
}

-(void) _tabBackward: (int)count
{
	if (count<1)
		count=1;
	while (count-- > 0 && x > 0)
	{
		do
		{
			x--;
		} while (x > 0 &&
		         !(tab_stop[x >> 5] & (1 << (x & 31))));
	}
	[ts ts_goto: x:y];
}

-(void) _screenAlignmentTest
{
	screen_char_t ch;

	ch.color=color;
	ch.attr=(intensity)|(underline<<2)|(reverse<<3)|(blink<<4);
	ch.ch='E';
	[ts ts_putChar: ch  count: width*height  offset: SCREEN(0,0)];
	gotoxy(currcons,0,0);
	last_char=ch;
	have_last_char=1;
}


#define insert_char(foo,nr) do { \
	[ts ts_shiftRow: y  at: x  delta: nr]; \
	[ts ts_putChar: video_erase_char  count: nr  at: x:y]; \
} while (0)

#define delete_char(foo,nr) do { \
	[ts ts_shiftRow: y  at: x+nr  delta: -nr]; \
	[ts ts_putChar: video_erase_char  count: nr  at: width-nr:y]; \
} while (0)


-(void) _csi_at: (unsigned int)nr
{
	if (nr > width - x)
		nr = width - x;
	else if (!nr)
		nr = 1;
	insert_char(currcons, nr);
}

-(void) _csi_L: (unsigned int)nr
{
	if (nr > height - y)
		nr = height - y;
	else if (!nr)
		nr = 1;

	scrdown(foo,y,bottom,nr);
}

-(void) _csi_P: (unsigned int)nr
{
	if (nr > width - x)
		nr = width - x;
	else if (!nr)
		nr = 1;
	delete_char(currcons, nr);
}

-(void) _csi_M: (unsigned int)nr
{
	if (nr > height - y)
		nr = height - y;
	else if (!nr)
		nr=1;
	scrup(foo,y,bottom,nr,NO);
}

#define set_kbd(foo)
#define clr_kbd(foo)


#define set_mode(foo,on_off) [self _set_mode: on_off]
-(void) _set_mode: (int) on_off
{
	int i;

	for (i=0; i<=npar; i++)
		if (ques) switch(par[i]) {	/* DEC private modes set/reset */
			case 1:			/* Cursor keys send ^[Ox/^[[x */
				if (on_off)
				{
					set_kbd(decckm);
				}
				else
				{
					clr_kbd(decckm);
				}
				break;
			case 3:	/* 80/132 mode switch unimplemented */
				NSDebugLLog(@"term",@"ignore _set_mode 3");
#if 0
				deccolm = on_off;
				(void) vc_resize(height, deccolm ? 132 : 80);
				/* this alone does not suffice; some user mode
				   utility has to change the hardware regs */
#endif
				break;
			case 5:			/* Inverted screen on/off */
				if (decscnm != on_off) {
					decscnm = on_off;
					[self _update_attr]; /* TODO? */
				}
				break;
			case 6:			/* Origin relative/absolute */
				decom = on_off;
				gotoxay(currcons,0,0);
				break;
			case 7:			/* Autowrap on/off */
				decawm = on_off;
				break;
			case 8:			/* Autorepeat on/off */
				NSDebugLLog(@"term",@"ignore _set_mode 8");
#if 0
				if (on_off)
					set_kbd(decarm);
				else
					clr_kbd(decarm);
#endif
				break;
			case 9:
				NSDebugLLog(@"term",@"ignore _set_mode 9");
#if 0
				report_mouse = on_off ? 1 : 0;
#endif
				break;
			case 25:		/* Cursor on/off */
				deccm = on_off;
				[ts ts_setCursorVisible: on_off];
				break;
			case 1048:		/* Save/restore cursor */
				if (on_off)
					save_cur(currcons);
				else
					restore_cur(currcons);
				break;
			case 1047:		/* Alternate screen buffer */
			case 1049:
				/* There is no alternate buffer in this screen API yet.
				   Preserve the cursor side effect expected by many apps. */
				if (par[i]==1049)
				{
					if (on_off)
						save_cur(currcons);
					else
						restore_cur(currcons);
				}
				break;
			case 1000:
				NSDebugLLog(@"term",@"ignore _set_mode 1000");
#if 0
				report_mouse = on_off ? 2 : 0;
#endif
				break;
		} else switch(par[i]) {		/* ANSI modes set/reset */
			case 3:			/* Monitor (display ctrls) */
				disp_ctrl = on_off;
				break;
			case 4:			/* Insert Mode on/off */
				decim = on_off;
				break;
			case 20:		/* Lf, Enter == CrLf/Lf */
				NSDebugLLog(@"term",@"ignore _set_mode 20");
#if 0
				if (on_off)
					set_kbd(lnm);
				else
					clr_kbd(lnm);
#endif
				break;
		}
}


#define setterm_command(foo) [self _setterm_command]
-(void) _setterm_command
{
	NSDebugLLog(@"term",@"ignore _setterm_command %i\n",par[0]);
	/* TODO: will need _update_attr */
	switch(par[0]) {
#if 0
		case 1:	/* set color for underline mode */
			if (can_do_color && par[1] < 16) {
				ulcolor = color_table[par[1]];
				if (underline)
					update_attr(currcons);
			}
			break;
		case 2:	/* set color for half intensity mode */
			if (can_do_color && par[1] < 16) {
				halfcolor = color_table[par[1]];
				if (intensity == 0)
					update_attr(currcons);
			}
			break;
#endif
		case 8:	/* store colors as defaults */
			def_color = color;
/*			if (hi_font_mask == 0x100)
				def_color >>= 1;*/
			[self _default_attr];
			[self _update_attr];
			break;
#if 0
		case 9:	/* set blanking interval */
			blankinterval = ((par[1] < 60) ? par[1] : 60) * 60 * HZ;
			poke_blanked_console();
			break;
		case 10: /* set bell frequency in Hz */
			if (npar >= 1)
				bell_pitch = par[1];
			else
				bell_pitch = DEFAULT_BELL_PITCH;
			break;
		case 11: /* set bell duration in msec */
			if (npar >= 1)
				bell_duration = (par[1] < 2000) ?
					par[1]*HZ/1000 : 0;
			else
				bell_duration = DEFAULT_BELL_DURATION;
			break;
		case 12: /* bring specified console to the front */
			if (par[1] >= 1 && vc_cons_allocated(par[1]-1))
				set_console(par[1] - 1);
			break;
		case 13: /* unblank the screen */
			poke_blanked_console();
			break;
		case 14: /* set vesa powerdown interval */
			vesa_off_interval = ((par[1] < 60) ? par[1] : 60) * 60 * HZ;
			break;
#endif
	}
}


-(void) processByte: (unsigned char)c
{
#define lf() [self _lineFeed]
#define ri() [self _reverseIndex]
#define cr() [self _carriageReturn]


#define cursor_report(foo,bar) do { \
	char buf[40]; \
 \
	sprintf(buf, "\033[%d;%dR", y + (decom ? top+1 : 1), x+1); \
	[ts ts_sendCString: buf]; \
} while (0)

#define status_report(foo) do { \
	[ts ts_sendCString: "\033[0n"]; \
} while (0)

#define VT102ID "\033[?6c"
#define respond_ID(foo) do { [ts ts_sendCString: VT102ID]; } while (0)
#define respond_secondary_ID(foo) do { [ts ts_sendCString: "\033[>0;0;0c"]; } while (0)


	switch (c)
	{
	case 0:
		return;
	case 7:
		if (vc_state==EStitle_buf)
		{
			NSString *new_title;
			title_buf[title_len]=0;
			new_title=[NSString stringWithCString: title_buf];
			[ts ts_setTitle: new_title  type: title_type];
			vc_state=ESnormal;

			return;
		}
		if (vc_state==ESosc_ignore)
		{
			vc_state=ESnormal;
			return;
		}
		NSBeep();
		return;
	case 8:
		if (x>0)
		{
			x--;
			[ts ts_goto: x:y];
		}
		return;
	case 9:
		[self _tabForward: 1];
		return;
	case 10: case 11:
		lf();
/*		if (!is_kbd(lnm))*/
			return;
	case 12:
		[self _clearDisplay];
		return;
	case 13:
		cr();
		return;
	case 14:
		charset = 1;
		translate = set_translate(G1_charset,currcons);
		disp_ctrl = 1;
		return;
	case 15:
		charset = 0;
		translate = set_translate(G0_charset,currcons);
		disp_ctrl = 0;
		return;
	case 24: case 26:
		vc_state = ESnormal;
		return;
	case 27:
		if (vc_state==EStitle_buf)
		{
			vc_state = EStitle_esc;
			return;
		}
		if (vc_state==ESosc_ignore)
		{
			vc_state = ESosc_ignore_esc;
			return;
		}
		vc_state = ESesc;
		return;
	case 127:
//		del(currcons);
		return;
	case 128+27:			// This kills UTF-8 unless we do some funky stuff
		if (!utf_count) {
			vc_state = ESsquare;
			return;
		}
	}
	switch(vc_state) {
	case ESesc:
		vc_state = ESnormal;
		switch (c) {
		case '[':
			vc_state = ESsquare;
			return;
		case ']':
			vc_state = ESnonstd;
			return;
		case '%':
			vc_state = ESpercent;
			return;
		case 'E':
			cr();
			lf();
			return;
		case 'M':
			ri();
			return;
		case 'D':
			lf();
			return;
		case 'H':
			tab_stop[x >> 5] |= (1 << (x & 31));
			return;
		case 'Z':
			respond_ID(foo);
			return;
		case '7':
			save_cur(currcons);
			return;
		case '8':
			restore_cur(currcons);
			return;
		case '(':
			vc_state = ESsetG0;
			return;
		case ')':
			vc_state = ESsetG1;
			return;
		case '#':
			vc_state = EShash;
			return;
		case 'c':
			[self _reset_terminal];
			return;
		case '>':  /* Numeric keypad */
			NSDebugLLog(@"term",@"ignore ESesc >  keypad");
#if 0
			clr_kbd(kbdapplic);
#endif
			return;
		case '=':  /* Appl. keypad */
			NSDebugLLog(@"term",@"ignore ESesc =  keypad");
#if 0
			set_kbd(kbdapplic);
#endif
			return;
		}
		return;
	case ESnonstd:
		switch (c)
		{
		case '0': case '1': case '2': case '3': case '4':
		case '5': case '6': case '7': case '8': case '9':
			vc_state=EStitle_semi;
			title_type=c-'0';
			return;

		case 'P':
			NSDebugLLog(@"term",@"ignore ESnonstd P");
#if 0
			for (npar=0; npar<NPAR; npar++)
				par[npar] = 0 ;
			npar = 0 ;
#endif
			vc_state = ESpalette;
			return;
		case 'R':
			NSDebugLLog(@"term",@"ignore ESnonstd R");
#if 0
			reset_palette(currcons);
#endif
			vc_state = ESnormal;
			return;
		}
		vc_state = ESosc_ignore;
		return;
	case EStitle_semi:
		if (c>='0' && c<='9')
		{
			title_type=title_type*10+c-'0';
		}
		else if (c==';')
		{
			if (title_type>=0 && title_type<=3)
			{
				vc_state=EStitle_buf;
				title_len=0;
			}
			else
				vc_state=ESosc_ignore;
		}
		else
			vc_state=ESosc_ignore;
		return;
	case EStitle_buf:
		if (title_len==TITLE_BUF_SIZE)
		{
			vc_state=ESnormal;
		}
		else
		{
			title_buf[title_len++]=c;
		}
		return;
	case EStitle_esc:
		if (c=='\\')
		{
			NSString *new_title;
			title_buf[title_len]=0;
			new_title=[NSString stringWithCString: title_buf];
			[ts ts_setTitle: new_title  type: title_type];
			vc_state=ESnormal;
		}
		else
		{
			if (title_len<TITLE_BUF_SIZE)
				title_buf[title_len++]=27;
			if (title_len<TITLE_BUF_SIZE)
				title_buf[title_len++]=c;
			else
				vc_state=ESnormal;
		}
		return;
	case ESosc_ignore:
		return;
	case ESosc_ignore_esc:
		if (c=='\\')
			vc_state=ESnormal;
		else
			vc_state=ESosc_ignore;
		return;
	case ESpalette:
		NSDebugLLog(@"term",@"ignore palette sequence (2)");
#if 0
		if ( (c>='0'&&c<='9') || (c>='A'&&c<='F') || (c>='a'&&c<='f') ) {
			par[npar++] = (c>'9' ? (c&0xDF)-'A'+10 : c-'0') ;
			if (npar==7) {
				int i = par[0]*3, j = 1;
				palette[i] = 16*par[j++];
				palette[i++] += par[j++];
				palette[i] = 16*par[j++];
				palette[i++] += par[j++];
				palette[i] = 16*par[j++];
				palette[i] += par[j];
				set_palette(currcons);
				vc_state = ESnormal;
			}
		} else
#endif
			vc_state = ESnormal;
		return;
	case ESsquare:
		for(npar = 0 ; npar < NPAR ; npar++)
			par[npar] = 0;
		npar = 0;
		csi_private = 0;
		csi_intermediate = 0;
		vc_state = ESgetpars;
		if (c == '[') { /* Function key */
			vc_state=ESfunckey;
			return;
		}
		ques = (c=='?');
		if (ques || c=='>')
		{
			csi_private = c;
			return;
		}
	case ESgetpars:
		if (c==';' && npar<NPAR-1) {
			npar++;
			return;
		} else if (c>='0' && c<='9') {
			par[npar] *= 10;
			par[npar] += c-'0';
			return;
		} else if (c>=' ' && c<='/') {
			csi_intermediate = c;
			return;
		} else vc_state=ESgotpars;
	case ESgotpars:
		vc_state = ESnormal;
		if (csi_intermediate) {
			if (csi_intermediate==' ' && c=='q')
				NSDebugLLog(@"term",@"ignore DECSCUSR");
			csi_intermediate = 0;
			return;
		}
		switch(c) {
		case 'h':
			set_mode(currcons,1);
			return;
		case 'l':
			set_mode(currcons,0);
			return;
		case 'c':
			if (csi_private=='>') {
				respond_secondary_ID(tty);
				return;
			}
			NSDebugLLog(@"term",@"ignore ESgotpars c");
#if 0
			if (ques) {
				if (par[0])
					cursor_type = par[0] | (par[1]<<8) | (par[2]<<16);
				else
					cursor_type = CUR_DEFAULT;
				return;
			}
#endif
			break;
		case 'n':
			if (!ques) {
				if (par[0] == 5)
					status_report(tty);
				else if (par[0] == 6)
					cursor_report(currcons,tty);
			}
			return;
		}
		if (csi_private && csi_private!='?') {
			csi_private = 0;
			return;
		}
		if (ques) {
			ques = 0;
			csi_private = 0;
			return;
		}
		switch(c) {
		case 'G': case '`':
			if (par[0]) par[0]--;
			gotoxy(currcons,par[0],y);
			return;
		case 'A':
			if (!par[0]) par[0]++;
			gotoxy(currcons,x,y-par[0]);
			return;
		case 'B': case 'e':
			if (!par[0]) par[0]++;
			gotoxy(currcons,x,y+par[0]);
			return;
		case 'C': case 'a':
			if (!par[0]) par[0]++;
			gotoxy(currcons,x+par[0],y);
			return;
		case 'D':
			if (!par[0]) par[0]++;
			gotoxy(currcons,x-par[0],y);
			return;
		case 'E':
			if (!par[0]) par[0]++;
			gotoxy(currcons,0,y+par[0]);
			return;
		case 'F':
			if (!par[0]) par[0]++;
			gotoxy(currcons,0,y-par[0]);
			return;
		case 'I':
			[self _tabForward: par[0]];
			return;
		case 'Z':
			[self _tabBackward: par[0]];
			return;
		case 'd':
			if (par[0]) par[0]--;
			gotoxay(currcons,x,par[0]);
			return;
		case 'H': case 'f':
			if (par[0]) par[0]--;
			if (par[1]) par[1]--;
			gotoxay(currcons,par[1],par[0]);
			return;
		case 'J':
			csi_J(currcons,par[0]);
			return;
		case 'K':
			csi_K(currcons,par[0]);
			return;
		case 'L':
			csi_L(currcons,par[0]);
			return;
		case 'M':
			csi_M(currcons,par[0]);
			return;
		case 'P':
			csi_P(currcons,par[0]);
			return;
		case 'S':
			if (!par[0]) par[0]++;
			scrup(foo,top,bottom,par[0],NO);
			return;
		case 'T':
			if (!par[0]) par[0]++;
			scrdown(foo,top,bottom,par[0]);
			return;
		case 'c':
			if (!par[0])
				respond_ID(tty);
			return;
		case 'g':
			if (!par[0])
				tab_stop[x >> 5] &= ~(1 << (x & 31));
			else if (par[0] == 3) {
				tab_stop[0] =
					tab_stop[1] =
					tab_stop[2] =
					tab_stop[3] =
					tab_stop[4] = 0;
			}
			return;
		case 'm':
			csi_m(currcons);
			return;
		case 'b':
			if (!par[0]) par[0]++;
			if (have_last_char)
			{
				int i;
				for (i=0; i<par[0]; i++)
					[self _putScreenChar: last_char];
			}
			return;
		case 'q': /* DECLL - but only 3 leds */
			/* map 0,1,2,3 to 0,1,2,4 */
			NSDebugLLog(@"term",@"ignore ESgotpars q");
#if 0
			if (par[0] < 4)
				setledstate(kbd_table + currcons,
					    (par[0] < 3) ? par[0] : 4);
#endif
			return;
		case 'r':
			if (!par[0])
				par[0]++;
			if (!par[1])
				par[1] = height;
			/* Minimum allowed region is 2 lines */
			if (par[0] < par[1] &&
			    par[1] <= height) {
				top=par[0]-1;
				bottom=par[1];
				gotoxay(currcons,0,0);
			}
			return;
		case 's':
			save_cur(currcons);
			return;
		case 'u':
			restore_cur(currcons);
			return;
		case 'X':
			csi_X(currcons, par[0]);
			return;
		case '@':
			csi_at(currcons,par[0]);
			return;
		case ']': /* setterm functions */
			setterm_command(currcons);
			return;
		}
		return;
	case ESpercent:
		vc_state = ESnormal;
		switch (c) {
		case '@':  /* defined in ISO 2022 */
			utf = 0;
			return;
		case 'G':  /* prelim official escape code */
		case '8':  /* retained for compatibility */
			utf = 1;
			return;
		}
		return;
	case ESfunckey:
		vc_state = ESnormal;
		return;
	case EShash:
		vc_state = ESnormal;
		if (c == '8')
		{
			[self _screenAlignmentTest];
			return;
		}
		NSDebugLLog(@"term",@"ignore EShash");
		return;
	case ESsetG0:
		if (c == '0')
			G0_charset = GRAF_MAP;
		else if (c == 'B')
			G0_charset = LAT1_MAP;
		else if (c == 'U')
			G0_charset = IBMPC_MAP;
		else if (c == 'K')
			G0_charset = USER_MAP;
		if (charset == 0)
			translate = set_translate(G0_charset,currcons);
		vc_state = ESnormal;
		return;
	case ESsetG1:
		if (c == '0')
			G1_charset = GRAF_MAP;
		else if (c == 'B')
			G1_charset = LAT1_MAP;
		else if (c == 'U')
			G1_charset = IBMPC_MAP;
		else if (c == 'K')
			G1_charset = USER_MAP;
		if (charset == 1)
			translate = set_translate(G1_charset,currcons);
		vc_state = ESnormal;
		return;
	default:
		vc_state = ESnormal;

		if (utf && c>0x7f)
		{
			if (utf_count && (c&0xc0)==0x80)
			{
				unich=(unich<<6)|(c&0x3f);
				utf_count--;
				if (utf_count)
					return;
			}
			else
			{
				if ((c & 0xe0) == 0xc0)
				{
					utf_count = 1;
					unich = (c & 0x1f);
				}
				else if ((c & 0xf0) == 0xe0)
				{
					utf_count = 2;
					unich = (c & 0x0f);
				}
				else if ((c & 0xf8) == 0xf0)
				{
					utf_count = 3;
					unich = (c & 0x07);
				}
				else if ((c & 0xfc) == 0xf8)
				{
					utf_count = 4;
					unich = (c & 0x03);
				}
				else if ((c & 0xfe) == 0xfc)
				{
					utf_count = 5;
					unich = (c & 0x01);
				}
				else
					utf_count = 0;
				return;
			}
		}
		else if (!iconv_state || translate!=translate_maps[0])
		{
			if (toggle_meta)
				c|=0x80;
			unich=translate[c];
		}
		else

		{
			char *inp;
			size_t in_size;
			char *outp;
			size_t out_size;

			int ret;

			if (toggle_meta)
				c|=0x80;

			/* TODO: there might be other cases where we should clear the
			buffer */
			if (input_buf_len==sizeof(input_buf))
			{
				NSLog(@"Warning: iconv() input buffer overrun!");
				input_buf_len=0;
			}
			input_buf[input_buf_len++]=c;

			inp=(char *)input_buf;
			in_size=input_buf_len;

			do
			{
				outp=(char *)&unich;
				out_size=4;
				utf_count=0;	// reset the non-internal utf count

				ret=iconv(iconv_state,(char **)&inp,&in_size,&outp,&out_size);

				if (out_size==0)
				{
					[self _putUnicodeCharacter: ntohl(unich)];
				}
				if (ret>=0)
					break;

				if (errno==EILSEQ)
				{ /* illegal input sequence. skip one byte and try again. */
					[self _putUnicodeCharacter: 0xfffd];
					in_size--;
					inp++;
				}

				if (errno==EINVAL)
				{ /* incomplete input sequence. wait for more input. */
					utf_count=1;	// FIXME: is this the right thing to do?
					break;
				}

				/* keep going while there's more input and the error was lack
				of output space */
			} while (in_size>0 && errno==E2BIG);

			/* adjust the buffer */
			if (in_size!=input_buf_len)
			{
				if (in_size)
					memmove(input_buf,inp,in_size);
				input_buf_len=in_size;
			}
			return;
		}

		{
			[self _putUnicodeCharacter: unich];
		}
		return;
	}
}


/*
Translates '\n' to '\r' when sending.
*/
-(void) sendString: (NSString *)s
{
	int l=[s length];
	unsigned int ucs;
	int i;

	if (iconv_input_state)
	{
		unsigned int *inp;
		size_t insize;
		char *outp;
		char buf[16+1];
		size_t outsize;
	
		for (i=0;i<l;i++)
		{
			ucs=[s characterAtIndex: i];
			if (ucs=='\n')
				ucs='\r';
			ucs=htonl(ucs);

			inp=&ucs;
			insize=4;
			outsize=sizeof(buf);
			outp=buf;
			iconv(iconv_input_state,(char **)&inp,&insize,&outp,&outsize);
			if (outsize!=sizeof(buf))
			{
				[ts ts_sendCString: buf  length: sizeof(buf)-outsize];
			}
			else
				NSBeep();
		}
	}
	else
	{
		unsigned char buf;
		for (i=0;i<l;i++)
		{
			ucs=[s characterAtIndex: i];
			if (ucs=='\n') ucs='\r';
			if (ucs<256)
			{
				buf=ucs;
				[ts ts_sendCString: (char *)&buf  length: 1];
			}
			else
				NSBeep();
		}
	}
}

-(void) handleKeyEvent: (NSEvent *)e
{
	NSString *s=TerminalStringByDroppingKeyEquivalentPrefix(
		[e charactersIgnoringModifiers]);
	NSString *characters=TerminalStringByDroppingKeyEquivalentPrefix(
		[e characters]);
	unsigned int mask=[e modifierFlags];
	unichar ch,ch2;

	const char *str;
	NSString *nstr;

	str=NULL;
	nstr=nil;
	ch2=0;

	if ([s length]>1)
	{
		NSDebugLLog(@"key",@" writing '%@'\n",characters);
		nstr=characters;
		ch=0;
	}
	else if ([s length]==0)
	{
		return;
	}
	else
	{
		ch=[s characterAtIndex: 0];
		switch (ch)
		{
		case '\e':
			if ([TerminalViewKeyboardPrefs doubleEscape])
				str="\e\e";
			else
				str="\e";
			break;

		case NSUpArrowFunctionKey   : str="\e[A"; break;
		case NSDownArrowFunctionKey : str="\e[B"; break;
		case NSLeftArrowFunctionKey : str="\e[D"; break;
		case NSRightArrowFunctionKey: str="\e[C"; break;

		case NSF1FunctionKey : str="\e[[A"; break;
		case NSF2FunctionKey : str="\e[[B"; break;
		case NSF3FunctionKey : str="\e[[C"; break;
		case NSF4FunctionKey : str="\e[[D"; break;
		case NSF5FunctionKey : str="\e[[E"; break;

		case NSF6FunctionKey : str="\e[17~"; break;
		case NSF7FunctionKey : str="\e[18~"; break;
		case NSF8FunctionKey : str="\e[19~"; break;
		case NSF9FunctionKey : str="\e[20~"; break;
		case NSF10FunctionKey: str="\e[21~"; break;
		case NSF11FunctionKey: str="\e[23~"; break;
		case NSF12FunctionKey: str="\e[24~"; break;

		case NSF13FunctionKey: str="\e[25~"; break;
		case NSF14FunctionKey: str="\e[26~"; break;
		case NSF15FunctionKey: str="\e[28~"; break;
		case NSF16FunctionKey: str="\e[29~"; break;
		case NSF17FunctionKey: str="\e[31~"; break;
		case NSF18FunctionKey: str="\e[32~"; break;
		case NSF19FunctionKey: str="\e[33~"; break;
		case NSF20FunctionKey: str="\e[34~"; break;

		case NSHomeFunctionKey    : str="\e[1~"; break;
		case NSInsertFunctionKey  : str="\e[2~"; break;
		case NSDeleteFunctionKey  : str="\e[3~"; break;
		case NSEndFunctionKey     : str="\e[4~"; break;
		case NSPageUpFunctionKey  : str="\e[5~"; break;
		case NSPageDownFunctionKey: str="\e[6~"; break;

		case 9:	// tab
			if (mask&NSShiftKeyMask)
				str="\e[Z";
			else
				nstr=characters;
			break;

		case 8: ch2=0x7f; break;
		case 3: ch2=0x0d; break;

		default:
			nstr=characters;
			break;
		}
	}

	{
		BOOL commandAsMeta=[TerminalViewKeyboardPrefs commandAsMeta];
		BOOL altIsNotMeta =[TerminalViewKeyboardPrefs altIsNotMeta];

		/*
		Thanks to different keyboard layouts and dumb default key handling
		in GNUstep, this is a bit complex. There seem to be two main cases:

		a. GNUstep has been correctly configured. Command is really command,
		alternate is really alternate, and is used as meta. AltGr isn't
		anything at all. No special options necessary.

		b. GNUstep is using the default settings. Left alt is command, right
		alt (which might be AltGr) is alternate. Users seem to actually want
		left alt to be meta, and, if right alt is AltGr, right alt not to be
		meta. Thus, when command-as-meta option is active, we intercept
		command presses and treat them as meta, and we ignore alternate.

		altIsNotMeta is needed to keep Alt as Alt and not as Meta.
		
		*/

		if ((commandAsMeta && (mask&NSCommandKeyMask)) ||
		    (!commandAsMeta && !altIsNotMeta && (mask&NSAlternateKeyMask)))
		{
			NSDebugLLog(@"key",@"  meta");
			[ts ts_sendCString: "\e"];
		}
	}

	if (nstr)
	{
		NSDebugLLog(@"key",@"  send NSString '%@'",nstr);
		[self sendString: nstr];
	}
	else if (str)
	{
		NSDebugLLog(@"key",@"  send '%s'",str);
		[ts ts_sendCString: str];
	}
	else if (ch2>256)
	{
		NSDebugLLog(@"key",@"  couldn't send %04x",ch2);
		NSBeep();
	}
	else if (ch2>0)
	{
		unsigned char tmp;
		tmp=ch2;
		NSDebugLLog(@"key",@"  send %02x",ch2);
		[ts ts_sendCString: (char *)&tmp  length: 1];
	}
}


- initWithTerminalScreen: (id<TerminalScreen>)ats  width: (int)w  height: (int)h
{
	const char *iconv_charset;

	if (!(self=[super init])) return nil;
	ts=ats;

	width=w;
	height=h;

	color=def_color=0x07;
	[self _reset_terminal];

	iconv_charset=[TerminalParser_LinuxPrefs characterSet];

	if (strcmp(iconv_charset,"iso-8859-1"))
	{
		iconv_state=iconv_open("ucs-4",iconv_charset);
		if (iconv_state==(iconv_t)-1)
		{
			iconv_state=NULL;
			NSLog(@"Warning: unable to create iconv handle for conversion from '%s'!",
				iconv_charset);
			NSLog(@"Falling back to iso-8859-1 (latin1).");
		}

		iconv_input_state=iconv_open(iconv_charset,"ucs-4");
		if (iconv_input_state==(iconv_t)-1)
		{
			iconv_input_state=NULL;
			NSLog(@"Warning: unable to create iconv handle for conversion to '%s'!",
				iconv_charset);
			NSLog(@"Falling back to iso-8859-1 (latin1).");
		}
	}

	return self;
}

-(void) dealloc
{
	if (iconv_state)
		iconv_close(iconv_state);
	if (iconv_input_state)
		iconv_close(iconv_input_state);
	[super dealloc];
}

-(void) setTerminalScreenWidth: (int)w height: (int)h
{
	y+=h-height;

	width=w;
	height=h;
	top=0;
	bottom=height;

	if (x>=width) x=width-1;
	if (x<0) x=0;
	if (y>=height) y=height-1;
	if (y<0) y=0;
}

@end
