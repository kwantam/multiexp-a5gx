# This file is part of multiexp-a5gx.
#
# multiexp-a5gx is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program. If not, see http://www.gnu.org/licenses/.

CFLAGS= -m64 -pedantic -pedantic-errors -std=gnu99 -Werror -Wall -Wextra -Wshadow -Wpointer-arith -Wcast-qual -Wformat=2 -Wstrict-prototypes -Wmissing-prototypes
CC := gcc
CXX := g++
CXXFLAGS := -m64 -pedantic -pedantic-errors -std=c++11 -Werror -Wall -Wextra -Wshadow -Wno-unused-parameter -Wpointer-arith -Wcast-qual -Wformat=2
LDFLAGS := -L. -static
LDLIBS := -lgmp -lmexpdrv -lrt

GHCFLAGS := -O

DEBUG ?= 0
ifeq ($(DEBUG),1)
        CFLAGS += -g -O0
        CXXFLAGS += -g -O0
else
        CFLAGS += -O2
        CXXFLAGS += -O2
endif

EXECS := flush_results_test multiplier_test dumpread convert_bases_test convert_exps_test batch_test
LIBS := libmexpdrv.a
OBJS := mexpdrv.o flush_results_test.o multiplier_test.o

all: $(LIBS) $(EXECS)

$(EXECS): $(LIBS)

lib%.a: %.o
	$(AR) rcsv $@ $<

.PHONY: clean
clean:
	rm -f $(OBJS) $(EXECS) $(LIBS)
