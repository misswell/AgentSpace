/* The two things the extension needs that Swift cannot express.
 *
 * `sys/kern_control.h`'s `ctl_info` and `sockaddr_ctl` are not importable into
 * Swift on this SDK ("structure not supported"), which makes `CTLIOCGINFO`
 * unusable from Swift even though the ioctl is exactly the right call. Defining
 * the same two structs here and doing the scan in C is both simpler and the
 * approach WireGuard's own macOS code takes, so it is a well-worn path rather
 * than a trick.
 *
 * The scan looks for the utun control socket NetworkExtension created for this
 * provider. There is no public API that hands that descriptor over; every
 * WireGuard-based macOS product finds it this way.
 */
#ifndef AGENTSPACE_TUNNEL_FD_H
#define AGENTSPACE_TUNNEL_FD_H

#include <stdint.h>

/// The descriptor of this process's utun interface, or -1.
int32_t agentspace_tunnel_fd(void);

#endif
