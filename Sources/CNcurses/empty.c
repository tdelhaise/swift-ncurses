#include "include/shim.h"
#include <locale.h>

attr_t swift_ncurses_attr_bold(void) { return A_BOLD; }
attr_t swift_ncurses_attr_dim(void) { return A_DIM; }
attr_t swift_ncurses_attr_underline(void) { return A_UNDERLINE; }
attr_t swift_ncurses_attr_reverse(void) { return A_REVERSE; }
attr_t swift_ncurses_attr_blink(void) { return A_BLINK; }
attr_t swift_ncurses_attr_standout(void) { return A_STANDOUT; }
attr_t swift_ncurses_attr_italic(void) { return A_ITALIC; }
attr_t swift_ncurses_attr_invisible(void) { return A_INVIS; }

int swift_ncurses_configure_stdscr_keypad(int enable) {
	return keypad(stdscr, enable ? TRUE : FALSE);
}

int swift_ncurses_color_pairs(void) {
	return COLOR_PAIRS;
}

mmask_t swift_ncurses_button1_pressed(void) { return BUTTON1_PRESSED; }
mmask_t swift_ncurses_button1_released(void) { return BUTTON1_RELEASED; }
mmask_t swift_ncurses_button2_pressed(void) { return BUTTON2_PRESSED; }
mmask_t swift_ncurses_button2_released(void) { return BUTTON2_RELEASED; }
mmask_t swift_ncurses_button3_pressed(void) { return BUTTON3_PRESSED; }
mmask_t swift_ncurses_button3_released(void) { return BUTTON3_RELEASED; }
#ifdef BUTTON4_PRESSED
mmask_t swift_ncurses_button4_pressed(void) { return BUTTON4_PRESSED; }
#else
mmask_t swift_ncurses_button4_pressed(void) { return 0; }
#endif
#ifdef BUTTON4_RELEASED
mmask_t swift_ncurses_button4_released(void) { return BUTTON4_RELEASED; }
#else
mmask_t swift_ncurses_button4_released(void) { return 0; }
#endif
#ifdef REPORT_MOUSE_POSITION
mmask_t swift_ncurses_report_mouse_position(void) { return REPORT_MOUSE_POSITION; }
#else
mmask_t swift_ncurses_report_mouse_position(void) { return 0; }
#endif

void swift_ncurses_setlocale(void) {
	setlocale(LC_ALL, "");
}
