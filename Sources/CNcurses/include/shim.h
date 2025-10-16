#pragma once

#if defined(__APPLE__)
  // Sur macOS, utiliser les headers système du SDK pour éviter les conflits
  #include <curses.h>
  #include <panel.h>
  #include <menu.h>
  #include <form.h>
#else
  // Sur Linux, utiliser les headers vendorisés ncursesw/*
  #include <ncursesw/curses.h>
  #include <ncursesw/panel.h>
  #include <ncursesw/menu.h>
  #include <ncursesw/form.h>
#endif

