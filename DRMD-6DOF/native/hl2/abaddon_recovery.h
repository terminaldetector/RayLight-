#ifndef ABADDON_RECOVERY_H
#define ABADDON_RECOVERY_H

#include "abaddon_mounts.h"

namespace abaddon
{
const float RecoveryCloudLife = 13.0f;
const float RecoveryReach = 112.0f;

struct RecoveryAmount
{
    float energy;
    int hull, armor;
    bool Any() const { return energy > 0 || hull > 0 || armor > 0; }
};

inline RecoveryAmount DroneSalvage(int maxHealth)
{
    const float ratio = maxHealth / 220.0f;
    const float scale = ratio < .62f ? .62f : (ratio > 2.3f ? 2.3f : ratio);
    const RecoveryAmount reward = {float(int(18 * scale)), int(12 * scale), 9};
    return reward;
}

inline RecoveryAmount FitRecovery(const RecoveryAmount &offer, float energy, int hp, int maxHP, int armor)
{
    const float chargeRoom = energy < FlightEnergyMax ? FlightEnergyMax - energy : 0;
    const int hpRoom = hp < maxHP ? maxHP - hp : 0;
    const int armorRoom = armor < 100 ? 100 - armor : 0;
    const RecoveryAmount delta = {
        offer.energy < chargeRoom ? offer.energy : chargeRoom,
        offer.hull < hpRoom ? offer.hull : hpRoom,
        offer.armor < armorRoom ? offer.armor : armorRoom
    };
    return delta;
}

inline float CloudOpacity(float remaining)
{
    if (remaining <= 0) return 0;
    return remaining >= 1.7f ? 1.0f : remaining / 1.7f;
}
}
#endif
