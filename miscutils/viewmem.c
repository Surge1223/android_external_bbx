//usage:#define viewmem_trivial_usage
//usage:	"address [data]"
//usage:#define viewmem_full_usage "\n\n"
//usage:       "Read physical address range from memory\n"
//usage:     "\naddress : memory address to start : <0xABCDEF>"
//usage:     "\ndata    : amount of data in HEX to view from start address : <0x10>"

#include "libbb.h"

#define INFO(fmt, ...) fprintf(stderr, "[INFO] " fmt, ##__VA_ARGS__)
#define ERR(fmt, ...) fprintf(stderr, "[ERR]  " fmt, ##__VA_ARGS__)
#define MAX(x, y) ((x) > (y) ? (x) : (y))
#define FATAL do { fprintf(stderr, "Error at line %d, file %s (%d) [%s]\n", \
  __LINE__, __FILE__, errno, strerror(errno)); exit(1); } while(0)

int viewmem_main(int argc, char **argv) MAIN_EXTERNALLY_VISIBLE;
int viewmem_main(int argc UNUSED_PARAM, char **argv)
{
    int fd;
    unsigned long addr = 0, size = sizeof(unsigned long), i, newaddr;
    void *buf;

	/* viewmem address [data] */

    if (argc < 2 || sscanf(argv[1], "0x%lx", &addr) != 1) {
        ERR("Wrong arguments!\n");
      //EVA: "Use with: ...\n"
        INFO("%s <0xABCDEF> [0x10] [/dev/mem]\n", argv[0]);
        return -1;
    }

    if (argc >= 3 && sscanf(argv[2], "0x%lx", &size) != 1) {
        ERR("Wrong size format!\n");
      //EVA: "Use HEX, i.e. 0x10" 
        return -1;
    }

    INFO("Reading %ld bytes at 0x%lx...\n", size, addr);

    fd = open(argc >= 4 && argv[3] ? argv[3] : "/dev/mem", O_RDONLY);
    if (!fd) {
        ERR("Couldn't open /dev/mem! (%s)\n", strerror(errno));
      // EVA: "Try using /dev/kmem."
      return -1;
    }

    newaddr = addr & ~(getpagesize()-1);
    buf = mmap(NULL, MAX(getpagesize(), size & ~(getpagesize()-1)), PROT_READ, MAP_SHARED, fd, newaddr);
    if (buf == MAP_FAILED) {
        ERR("Couldn't map 0x%lx (%d %s)!\n", addr, errno, strerror(errno));
        close(fd);
        return -1;
    }

    for (i = 0; i < size; i += sizeof(unsigned long)) {
        char temp[4];
        *(unsigned long*)temp = *(unsigned long*)(buf + (addr-newaddr) + i);
        fwrite(temp, sizeof(temp), 1, stdout);
    }

    munmap(buf, size);
    close(fd);
    return 0;
}

