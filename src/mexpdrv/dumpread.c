// This file is part of multiexp-a5gx.
//
// multiexp-a5gx is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License
// along with this program. If not, see http://www.gnu.org/licenses/.

#include <unistd.h>
#include <stdlib.h>
#include <sys/types.h>
#include <sys/stat.h>
#include <fcntl.h>
#include <stdio.h>

#include "mexpdrv.h"

// 26-bit address space
#define MEMSIZE (1 << 20)
#define RDDEV "/dev/xillybus_r"
#define WRDEV "/dev/xillybus_w"

int main(int argc, char **argv) {
    (void) argc;
    (void) argv;

    int w_fd = open(WRDEV, O_WRONLY);
    if (w_fd < 0) {
        perror("Could not open wfd");
        exit(-1);
    }

    int r_fd = open(RDDEV, O_RDONLY);
    if (r_fd < 0) {
        perror("Could not open rfd");
        exit(-2);
    }

    uint32_t wval = 0x40000000;
    uint32_t resp;
    write(w_fd, &wval, 4);
    read(r_fd, &resp, 4);
    printf("%x\n", resp);
    write(w_fd, &wval, 4);
    read(r_fd, &resp, 4);
    printf("%x\n", resp);
    wval = 0x20000000;
    write(w_fd, &wval, 4);
    int count = 0;
    while (count++ < 41) {
        read(r_fd, &resp, 4);
        printf("%x\n", resp);
    }

    return 0;
}
