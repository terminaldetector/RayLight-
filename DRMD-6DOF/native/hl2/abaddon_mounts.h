#ifndef ABADDON_MOUNTS_H
#define ABADDON_MOUNTS_H

#include "abaddon_flight_math.h"

namespace abaddon
{
enum { MountCount = 4, MountSocketCount = 2 };

const float MountFireInterval = 0.06f;
const float MountDamage = 12.0f;
const float MountRange = 8192.0f;
const float PulseSpeed = 5000.0f;
const float PlasmaSpeed = 3200.0f;
const float FlightEnergyMax = 100.0f;
const float FlightEnergyRecharge = 6.72f;
const float PlasmaCost = 8.0f;
const float PlasmaInterval = 0.45f;
const float PlasmaRecharge = 1.7f;
enum { PlasmaCapacity = 6, PlasmaShotFlag = 16 };

inline int RefitPlasmaMount(int current, int requested, bool installPlasma)
{
    if (requested < 0 || requested >= MountCount)
        return current;
    return installPlasma ? requested : (current == requested ? -1 : current);
}

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

inline MountGeometry GetMountGeometry(const Vec3& center, const FlightBasis& basis, int mount, int socket,
                                      bool plasma = false)
{
    // Model +Y points left, so the first emitter is on the left of its own receiver.
    const Vec3 emitter(15.55f, plasma ? 0.0f : (socket == 0 ? -2.75f : 2.75f), 0.0f);
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

struct PlasmaFeed
{
    float energy;
    float readyAt;
    int rounds;

    void Advance(float now, float seconds)
    {
        if (seconds > 0.0f)
        {
            const float charged = energy + seconds * FlightEnergyRecharge;
            energy = charged < FlightEnergyMax ? charged : FlightEnergyMax;
        }
        if (rounds == 0 && now >= readyAt)
            rounds = PlasmaCapacity;
    }

    bool Ready(float now) const
    {
        return rounds > 0 && energy >= PlasmaCost && now >= readyAt;
    }

    void Fired(float now)
    {
        energy -= PlasmaCost;
        --rounds;
        readyAt = now + (rounds == 0 ? PlasmaRecharge : PlasmaInterval);
    }
};
}  // namespace abaddon

#endif
