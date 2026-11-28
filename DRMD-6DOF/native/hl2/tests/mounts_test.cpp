#include "../abaddon_mounts.h"

#include <cmath>
#include <cstdio>

namespace
{
int passed = 0;
int failed = 0;

void Check(bool result, const char* description)
{
    std::printf("%s | %s\n", result ? "PASS" : "FAIL", description);
    if (result)
        ++passed;
    else
        ++failed;
}

bool Near(const abaddon::Vec3& actual, const abaddon::Vec3& expected)
{
    return (actual - expected).LengthSquared() < 0.001f;
}
}

int main()
{
    using namespace abaddon;
    const FlightBasis level = {Vec3(1, 0, 0), Vec3(0, -1, 0), Vec3(0, 0, 1)};
    const FlightBasis rolled = {Vec3(1, 0, 0), Vec3(0, 0, -1), Vec3(0, -1, 0)};
    const Vec3 center(100, 200, 300);

    const Vec3 mountPoints[MountCount] = {
        Vec3(105, 224, 297), Vec3(105, 176, 297), Vec3(93, 213, 326), Vec3(104, 185, 280)
    };
    for (int mount = 0; mount < MountCount; ++mount)
        Check(Near(GetMountGeometry(center, level, mount, 0).mount, mountPoints[mount]),
              "mount starts at its authored offset");
    Check(Near(GetMountGeometry(center, level, 0, 0).muzzle, Vec3(120.55f, 226.75f, 297)),
          "left emitter is forward and outside the receiver");
    Check(Near(GetMountGeometry(center, level, 0, 1).muzzle, Vec3(120.55f, 221.25f, 297)),
          "second emitter keeps its distinct side");
    Check(Near(GetMountGeometry(center, rolled, 0, 0).muzzle, Vec3(120.55f, 203, 326.75f)),
          "roll rotates receiver and socket about the flight axis");
    Check(Near(GetMountGeometry(center, rolled, 2, 1).muzzle, Vec3(108.55f, 174, 310.25f)),
          "top mount and its second socket follow the full basis");

    MountCycle mounts[MountCount];
    Check(mounts[0].BeginAttempt(1.0f) && mounts[1].BeginAttempt(1.0f) &&
          mounts[2].BeginAttempt(1.0f) && mounts[3].BeginAttempt(1.0f),
          "four channels can fire on the same simulation step");
    mounts[0].Fired();
    Check(mounts[0].socket == 1 && mounts[1].socket == 0 &&
          mounts[2].socket == 0 && mounts[3].socket == 0,
          "successful shot cycles only its own socket");
    Check(!mounts[0].BeginAttempt(1.03f) && mounts[0].BeginAttempt(1.061f),
          "held channel honors sixty millisecond cooldown");
    Check(!mounts[0].BeginAttempt(1.07f) && mounts[1].BeginAttempt(1.07f),
          "one mount's cooldown cannot block another");
    Check(mounts[1].socket == 0, "blocked attempt can throttle without changing socket");
    mounts[0].Fired();
    Check(mounts[0].socket == 0, "second shot wraps to the first socket");
    mounts[0] = MountCycle();
    Check(mounts[0].socket == 0 && mounts[0].BeginAttempt(0.0f),
          "new pilot life starts with a ready mount and first socket");

    Check(Near(GetMountGeometry(center, rolled, 2, 0, true).muzzle, Vec3(108.55f, 174, 313)),
          "the plasma emitter stays centered in the rolled mount");
    Check(RefitPlasmaMount(2, 0, true) == 0 && RefitPlasmaMount(2, 0, false) == 2,
          "refit moves the single plasma module and keeps the other mounts kinetic");
    Check(RefitPlasmaMount(2, 2, false) == -1 && RefitPlasmaMount(2, 4, true) == 2,
          "refit can stow plasma and ignores an invalid mount");
    PlasmaFeed plasma = {FlightEnergyMax, 0.0f, PlasmaCapacity};
    Check(plasma.Ready(1.0f), "a charged plasma module is ready");
    plasma.Fired(1.0f);
    Check(plasma.energy == 92.0f && plasma.rounds == 5 &&
          !plasma.Ready(1.44f) && plasma.Ready(1.46f),
          "accepted shot spends energy and one cycle, with its own cadence");
    for (int round = 1; round < PlasmaCapacity; ++round)
        plasma.Fired(1.0f + round * 0.5f);
    plasma.Advance(5.19f, 0.0f);
    Check(plasma.rounds == 0 && !plasma.Ready(5.19f),
          "empty capacitor blocks another shot before the refill interval");
    plasma.Advance(5.21f, 0.0f);
    Check(plasma.rounds == PlasmaCapacity && plasma.energy == 52.0f && plasma.Ready(5.21f),
          "capacitor refill restores cycles without restoring spent energy");
    plasma.energy = 7.0f;
    Check(!plasma.Ready(6.0f), "loaded plasma cannot spend unavailable energy");
    plasma.Advance(6.5f, 0.5f);
    Check(plasma.Ready(6.5f) && plasma.energy > PlasmaCost, "energy recharges at the balanced feed rate");
    plasma.Advance(30.0f, 23.5f);
    Check(plasma.energy == FlightEnergyMax, "recharge is capped at the flight reservoir");

    std::printf("%d passed, %d failed\n", passed, failed);
    return failed ? 1 : 0;
}
