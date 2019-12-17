MODE_FILE=.mode
MODE ?= $(shell cat $(MODE_FILE) 2>/dev/null || echo release)

SOURCE  = src
UTILS = $(SOURCE)/util
LIBS = $(SOURCE)/lib
INCLUDES = $(SOURCE)/include
MODULES = $(SOURCE)/modules

# Optional Module Switches
DOME_OPT_FFI=0
ifeq ($(DOME_OPT_FFI),1)
	DOME_OPTS ?= -D DOME_OPT_FFI=1
endif

BUILD_VALUE=$(shell git rev-parse --short HEAD)
CC = cc
CFLAGS = $(DOME_OPTS) -std=c99 -pedantic -Wall  -Wextra -Wno-unused-parameter -Wno-unused-function -Wno-unused-value `sdl2-config --cflags`
IFLAGS = -isystem $(INCLUDES)
SDLFLAGS= `sdl2-config --libs`
LDFLAGS = -L$(LIBS) $(SDLFLAGS) -lm

ifeq ($(DOME_OPT_FFI),1)
  LDFLAGS  += -lffi
  FFI_DEPS = $(LIBS)/libffi $(LIBS)/libffi.a $(INCLUDES)/ffi.h
endif

EXENAME = dome


ifeq ($(MODE), debug)
	LDFLAGS += -lwrend
	CFLAGS += -g -fsanitize=address -O0
  $(shell echo $(MODE) > .mode)
else
	LDFLAGS += -lwren
	CFLAGS += -O3
  $(shell echo $(MODE) > .mode)
endif

SYS=$(shell uname -s)

ifneq (, $(findstring Darwin, $(SYS)))
	CFLAGS += -Wno-incompatible-pointer-types-discards-qualifiers
endif

ifneq (, $(findstring MINGW, $(SYS)))
	CFLAGS += -Wno-discarded-qualifiers
	ifdef ICON_OBJECT_FILE
	CFLAGS += $(ICON_OBJECT_FILE)
endif
SDLFLAGS := -mwindows $(SDLFLAGS)
endif

ifneq (, $(findstring Linux, $(SYS)))
	CFLAGS += -Wno-discarded-qualifiers
endif



.PHONY: all clean reset cloc $(lIBS)/libffi $(LIBS)/wren
all: $(EXENAME)

$(LIBS)/libffi/autogen.sh:
	git submodule update --init -- $(LIBS)/libffi
$(LIBS)/libffi: $(LIBS)/libffi/autogen.sh

$(LIBS)/wren/Makefile: 
	git submodule update --init -- $(LIBS)/wren
$(LIBS)/wren: $(LIBS)/wren/Makefile
	
$(LIBS)/libffi.a: $(LIBS)/libffi
	./setup_ffi.sh

$(LIBS)/libwren.a: $(LIBS)/wren
	./setup_wren.sh

$(INCLUDES)/ffi.h: $(LIBS)/libffi.a
$(INCLUDES)/ffitarget.h: $(LIBS)/libffi.a
	
$(INCLUDES)/wren.h: $(LIBS)/libwren.a
	cp src/lib/wren/src/include/wren.h src/include/wren.h

$(MODULES)/*.inc: $(UTILS)/embed.c $(MODULES)/*.wren
	cd $(UTILS) && ./generateEmbedModules.sh

$(EXENAME): $(SOURCE)/*.c $(MODULES)/*.c $(UTILS)/font.c $(INCLUDES) $(MODULES)/*.inc $(INCLUDES)/wren.h $(LIBS)/libwren.a $(FFI_DEPS)
	$(CC) $(CFLAGS) $(SOURCE)/main.c -o $(EXENAME) $(LDFLAGS) $(IFLAGS)
	$(warning $(MODE))
ifneq (, $(findstring Darwin, $(SYS)))
	install_name_tool -change /usr/local/opt/sdl2/lib/libSDL2-2.0.0.dylib \@executable_path/libSDL2.dylib $(EXENAME)
endif

# Used for the example game FFI test
libadd.so: test/add.c
	$(CC) -O -fno-common -c test/add.c $(IFLAGS) -o test/add.o -g
	$(CC) -flat_namespace -bundle -undefined suppress -o libadd.so test/add.o
	rm test/add.o

reset:
	git submodule foreach --recursive git clean -xfd
	rm -rf .mode $(EXENAME) $(LIBS)/libwren.a $(MODULES)/*.inc $(INCLUDES)/wren.h $(LIBS)/libwrend.a $(LIBS)/libffi.a $(INCLUDES)/ffi.h $(INCLUDES)/ffitarget.h

clean:
	rm -rf $(EXENAME) $(MODULES)/*.inc

# Counts the number of lines used, for vanity
cloc:
	cloc --by-file --force-lang="java",wren --fullpath --not-match-d "util|include|lib" -not-match-f ".inc" src

