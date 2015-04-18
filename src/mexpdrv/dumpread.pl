#!/usr/bin/perl -w
#
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

use strict;

my $fh;
my $wfh;
open $fh, "<", "/dev/xillybus_r";
open $wfh, ">", "/dev/xillybus_w";

syswrite($wfh, pack("C*", (0, 0, 0, 64)));

my $bar;
while (sysread($fh, $bar, 4)) {
    my @obytes = unpack("C*", $bar);
    map { printf("%x ", $_) } @obytes;
    print "\n";
}
