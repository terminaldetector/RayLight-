#ifndef ABADDON_MOUNTS_H
#define ABADDON_MOUNTS_H

#include "abaddon_flight_math.h"

namespace abaddon
{
enum { MountCount = 4, MountSocketCount = 2 };

const float MountFireInterval = 0.06f;
const float MountDamage = 12.0f;
const float MountRange = 8192.0f;

// Forward, right and up, from d6_arsenal.lua. Mine placement is separate.
inline Vec3 MountOffset(int mount)
{
    const Vec3 offsets[MountCount] = {
        Vec3(5, -24, -3), Vec3(5, 24, -3), Vec3(-7, -13, 26), Vec3(4, 15, -20)
    };
    return offsets[mount];
}

inline Vec3 TransformOffset(const FlightBasis& basis, const Vec3& offset)
{
    return basis.forward * offset.x + basis.right * offset.y + basis.up * offset.z;
}

struct MountGeometry
{
    Vec3 mount;
    Vec3 muzzle;
};

inline MountGeometry GetMountGeometry(const Vec3& center, const FlightBasis& basis, int mount, int socket)
{
    // Model +Y points left, so the first emitter is on the left of its own receiver.
    const Vec3 emitter(15.55f, socket == 0 ? -2.75f : 2.75f, 0.0f);
    const Vec3 receiver = center + TransformOffset(basis, MountOffset(mount));
    const MountGeometry result = {receiver, receiver + TransformOffset(basis, emitter)};
    return result;
}

struct MountCycle
{
    MountCycle() : nextAttempt(0.0f), socket(0) {}

    bool BeginAttempt(float now)
    {
        if (now < nextAttempt)
            return false;
        nextAttempt = now + MountFireInterval;
        return true;
    }

    void Fired() { socket = (socket + 1) % MountSocketCount; }

    float nextAttempt;
    int socket;
};
}  // namespace abaddon

#endif
