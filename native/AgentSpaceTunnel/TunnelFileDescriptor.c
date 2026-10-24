/* SPDX-License-Identifier: MIT */
#include "TunnelFileDescriptor.h"

#include <net/if.h>
#include <string.h>
#include <sys/ioctl.h>
#include <sys/socket.h>
#include <sys/types.h>
#include <unistd.h>

/* These mirror <sys/kern_control.h>, which Swift cannot import. The values and
 * layout are fixed by the kernel ABI; they are copied rather than invented. */
struct agentspace_ctl_info {
    uint32_t ctl_id;
    char ctl_name[96];
};

struct agentspace_sockaddr_ctl {
    unsigned char sc_len;
    unsigned char sc_family;
    uint16_t ss_sysaddr;
    uint32_t sc_id;
    uint32_t sc_unit;
    uint32_t sc_reserved[5];
};

#define AGENTSPACE_AF_SYSTEM 32
#define AGENTSPACE_CTLIOCGINFO 0xc0644e03UL /* _IOWR('N', 3, struct ctl_info) */

int32_t agentspace_tunnel_fd(void) {
    struct agentspace_ctl_info info;
    memset(&info, 0, sizeof(info));
    const char *name = "com.apple.net.utun_control";
    strncpy(info.ctl_name, name, sizeof(info.ctl_name) - 1);

    for (int fd = 0; fd <= 1024; fd++) {
        struct agentspace_sockaddr_ctl address;
        socklen_t length = sizeof(address);
        if (getpeername(fd, (struct sockaddr *)&address, &length) != 0) {
            continue;
        }
        if (address.sc_family != AGENTSPACE_AF_SYSTEM) {
            continue;
        }
        if (info.ctl_id == 0 && ioctl(fd, AGENTSPACE_CTLIOCGINFO, &info) != 0) {
            continue;
        }
        if (address.sc_id == info.ctl_id) {
            return (int32_t)fd;
        }
    }
    return -1;
}
