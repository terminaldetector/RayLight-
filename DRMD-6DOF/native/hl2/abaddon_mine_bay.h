#ifndef ABADDON_MINE_BAY_H
#define ABADDON_MINE_BAY_H

#include "abaddon_mounts.h"

namespace abaddon
{
enum MineType { PlasmaMine = 0, GravityMine = 1 };
enum MinePhase { MineArming, MineActive, MineExpired };
enum { InitialMines = 2, MineCapacity = 6, SupplyMines = 2 };
const float MineHull = 14.0f;  // Encloses both studio models at any roll angle.

struct MineProfile
{
    float cost, cooldown, armDelay, life, senseRadius, blastRadius, damage;
    int activeLimit;
};

inline const MineProfile &MineStats(MineType type)
{
    static const MineProfile plasma = {25, 1, .8f, 30, 180, 260, 100, 4};
    static const MineProfile gravity = {30, 1.5f, 0, 8, 500, 300, 90, 3};
    return type == GravityMine ? gravity : plasma;
}

inline Vec3 MineReleasePoint(const Vec3 &center, const FlightBasis &basis)
{
    return center + TransformOffset(basis, Vec3(100, 0, -18));
}

struct MineFeed
{
    int reserve;
    float readyAt;
    bool Ready(float now, float energy, MineType type) const
    {
        return reserve > 0 && now >= readyAt && energy >= MineStats(type).cost;
    }
    void Fired(float now, float &energy, MineType type)
    {
        --reserve;
        energy -= MineStats(type).cost;
        readyAt = now + MineStats(type).cooldown;
    }
    int Restock() const
    {
        const int next = reserve + SupplyMines;
        return next < MineCapacity ? next : MineCapacity;
    }
};

inline float MineFalloff(float distance, float radius)
{
    return distance < radius ? 1.0f - distance / radius : 0.0f;
}

inline MinePhase PhaseAt(float now, float armAt, float expireAt)
{
    if (now >= expireAt)
        return MineExpired;
    return now < armAt ? MineArming : MineActive;
}
}
#endif
