#include "../abaddon_mine_bay.h"
#include <cstdio>

static int failures;

static void Check(bool ok, const char *name)
{
    std::printf("%s | %s\n", ok ? "PASS" : "FAIL", name);
    if (!ok)
        ++failures;
}

int main()
{
    using namespace abaddon;
    MineFeed bay = {InitialMines, 0};
    float energy = 100;
    const FlightBasis level = {Vec3(1,0,0), Vec3(0,-1,0), Vec3(0,0,1)};
    const FlightBasis inverted = {Vec3(1,0,0), Vec3(0,1,0), Vec3(0,0,-1)};
    const FlightBasis climb = {Vec3(0,0,1), Vec3(0,-1,0), Vec3(-1,0,0)};
    const Vec3 center(8,-7,40);
    Check((MineReleasePoint(center, level) - Vec3(108,-7,22)).LengthSquared() < .001f, "level bay port");
    Check((MineReleasePoint(center, inverted) - Vec3(108,-7,58)).LengthSquared() < .001f, "inverted bay port");
    Check((MineReleasePoint(center, climb) - Vec3(26,-7,140)).LengthSquared() < .001f, "vertical bay port");
    Check(bay.reserve == 2 && bay.Ready(1, energy, PlasmaMine), "two mines on spawn");
    Check(!bay.Ready(1, 24.9f, PlasmaMine) && bay.Ready(1,25, PlasmaMine), "plasma energy threshold");
    Check(!bay.Ready(1, 29.9f, GravityMine) && bay.Ready(1,30, GravityMine), "gravity energy threshold");
    bay.Fired(1, energy, PlasmaMine);
    Check(bay.reserve == 1 && energy == 75, "plasma debit");
    Check(!bay.Ready(1.99f, energy, GravityMine), "switching payload retains cooldown");
    Check(bay.Ready(2, energy, GravityMine), "second mine ready at exact deadline");
    bay.Fired(2, energy, GravityMine);
    Check(bay.reserve == 0 && energy == 45 && bay.readyAt == 3.5f, "gravity debit and shared cooldown");
    Check(!bay.Ready(4, energy, PlasmaMine), "empty bay cannot fire");
    bay.reserve = bay.Restock();
    Check(bay.reserve == 2 && !bay.Ready(3, energy, PlasmaMine), "supply gives two without resetting timer");
    bay.reserve = 5;
    Check(bay.Restock() == 6, "partial crate obeys maximum");
    bay.reserve = 6;
    Check(bay.Restock() == bay.reserve, "full bay leaves crate available");
    Check(MineStats(PlasmaMine).activeLimit == 4 && MineStats(GravityMine).activeLimit == 3, "separate deployed limits");
    Check(std::fabs(MineStats(PlasmaMine).armDelay - .8f) < .00001f && MineStats(PlasmaMine).life == 30, "plasma arming delay and expiry");
    Check(MineStats(GravityMine).armDelay == 0 && MineStats(GravityMine).life == 8, "gravity field timing");
    Check(MineFalloff(0,260) == 1 && MineFalloff(130,260) == .5f, "spherical falloff");
    Check(MineFalloff(260,260) == 0 && MineFalloff(330,260) == 0, "no damage beyond radius");
    Check(PhaseAt(4.7f,4.8f,34) == MineArming, "plasma ignores nearby actors before arming");
    Check(PhaseAt(4.8f,4.8f,34) == MineActive, "participates at the arming deadline");
    Check(PhaseAt(33.9f,4.8f,34) == MineActive, "armed mine survives up to expiry");
    Check(PhaseAt(34,4.8f,34) == MineExpired, "expiry takes precedence over sensing");
    Check(PhaseAt(4,4,12) == MineActive && PhaseAt(12.5f,4,12) == MineExpired, "immediate gravity field and late tick expiry");
    return failures ? 1 : 0;
}
