/* The three functions this product uses from wireguard-go.
 *
 * Declared by hand rather than vendoring WireGuardKit: the library's Swift layer
 * exists to parse `wg-quick` files and manage Apple's settings, and AgentSpace
 * already builds the UAPI text in `AgentSpaceCore` (where it is unit-tested and
 * measured against a real device, §398). All that is left is starting and
 * stopping the device against a utun file descriptor.
 */
#ifndef AGENTSPACE_WIREGUARD_UAPI_H
#define AGENTSPACE_WIREGUARD_UAPI_H

#include <stdint.h>
#include <stdbool.h>

#include "TunnelFileDescriptor.h"

/// Apply a UAPI configuration to a tun file descriptor. Returns a handle > 0, or
/// a negative value on failure.
extern int wgTurnOn(const char *settings, int32_t tun_fd);

/// Stop the device behind a handle from `wgTurnOn`.
extern void wgTurnOff(int handle);

/// The wireguard-go version string. Owned by the library; do not free.
extern const char *wgVersion(void);

/// A logger callback. `context` is passed through unchanged.
typedef void (*agentspace_wg_logger_t)(void *context, int level, const char *message);

/// Install a logger. Passing NULL removes it.
extern void wgSetLogger(void *context, agentspace_wg_logger_t logger);

#endif
