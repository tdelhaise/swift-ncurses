#pragma once

#if defined(__APPLE__)
  // Sur macOS, utiliser les headers système du SDK pour éviter les conflits
  #include <curses.h>
  #include <util.h>
  #include <sys/ioctl.h>
  typedef struct panel PANEL;
  extern PANEL *new_panel(WINDOW *);
  extern int del_panel(PANEL *);
  extern int show_panel(PANEL *);
  extern int hide_panel(PANEL *);
  extern int top_panel(PANEL *);
  extern int bottom_panel(PANEL *);
  extern void update_panels(void);
#else
  // Sur Linux, utiliser les headers vendorisés ncursesw/*
  #include <ncursesw/curses.h>
  #include <ncursesw/panel.h>
  #include <ncursesw/menu.h>
#include <ncursesw/form.h>
#include <pty.h>
#include <sys/ioctl.h>
#endif

#ifndef A_ITALIC
#define A_ITALIC A_NORMAL
#endif

#ifdef __cplusplus
extern "C" {
#endif

attr_t swift_ncurses_attr_bold(void);
attr_t swift_ncurses_attr_dim(void);
attr_t swift_ncurses_attr_underline(void);
attr_t swift_ncurses_attr_reverse(void);
attr_t swift_ncurses_attr_blink(void);
attr_t swift_ncurses_attr_standout(void);
attr_t swift_ncurses_attr_italic(void);
attr_t swift_ncurses_attr_invisible(void);

int swift_ncurses_configure_stdscr_keypad(int enable);
int swift_ncurses_color_pairs(void);
mmask_t swift_ncurses_button1_pressed(void);
mmask_t swift_ncurses_button1_released(void);
mmask_t swift_ncurses_button2_pressed(void);
mmask_t swift_ncurses_button2_released(void);
mmask_t swift_ncurses_button3_pressed(void);
mmask_t swift_ncurses_button3_released(void);
mmask_t swift_ncurses_button4_pressed(void);
mmask_t swift_ncurses_button4_released(void);
mmask_t swift_ncurses_report_mouse_position(void);
void swift_ncurses_setlocale(void);
int swift_ncurses_openpty(int *masterFd, int *slaveFd, int rows, int cols);
int swift_ncurses_set_winsize(int fd, int rows, int cols);

#ifdef __cplusplus
}
#endif
