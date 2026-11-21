#include "../abaddon_flight_math.h"

#include <cmath>
#include <iostream>

namespace
{
using abaddon::FlightBasis;
using abaddon::FlightWish;
using abaddon::StepFlight;
using abaddon::Vec3;

int passed = 0;
int failed = 0;

float Length(const Vec3& vector)
{
    return std::sqrt(vector.LengthSquared());
}

bool Near(const Vec3& actual, const Vec3& expected, float tolerance = 0.005f)
{
    return Length(actual - expected) <= tolerance;
}

void Check(const char* scenario, bool okay)
{
    std::cout << (okay ? "PASS" : "FAIL") << " | " << scenario << '\n';
    if (okay)
        ++passed;
    else
        ++failed;
}

Vec3 Simulate(Vec3 start, const Vec3& wish, float seconds, int ticks)
{
    for (int tick = 0; tick < ticks; ++tick)
        start = StepFlight(start, wish, seconds / ticks);
    return start;
}
}  // namespace

int main()
{
    const FlightBasis level = {Vec3(1, 0, 0), Vec3(0, -1, 0), Vec3(0, 0, 1)};
    const FlightBasis banked = {Vec3(1, 0, 0), Vec3(0, 0, -1), Vec3(0, -1, 0)};
    const FlightBasis pitched = {Vec3(0, 0, 1), Vec3(0, -1, 0), Vec3(-1, 0, 0)};
    const Vec3 idle;
    const Vec3 forward = FlightWish(level, 1, 0, 0);
    const Vec3 diagonal = FlightWish(level, 1, 1, 1);

    Check("zero input preserves a hover at rest", Near(Simulate(idle, idle, 4.0f, 264), idle));
    Check("local forward movement follows the nose", Near(forward, Vec3(1, 0, 0)));
    Check("local strafe follows right", Near(FlightWish(level, 0, 1, 0), Vec3(0, -1, 0)));
    Check("local rise and fall are opposite", Near(FlightWish(level, 0, 0, -1), Vec3(0, 0, -1)));
    Check("roll rotates vertical thrust to the side", Near(FlightWish(banked, 0, 0, 1), Vec3(0, -1, 0)));
    Check("roll rotates strafe downwards", Near(FlightWish(banked, 0, 1, 0), Vec3(0, 0, -1)));
    Check("pitch allows thrust straight up", Near(FlightWish(pitched, 1, 0, 0), Vec3(0, 0, 1)));
    Check("three axes normalize combined input", Near(diagonal, Vec3(1, -1, 1) * (1.0f / std::sqrt(3.0f))));
    Check("half input stays proportional", Near(Simulate(idle, FlightWish(level, .5f, 0, 0), 1.0f, 66), Vec3(1100, 0, 0)));
    Check("first tenth of a second applies bounded acceleration", Near(StepFlight(idle, forward, .1f), Vec3(420, 0, 0)));
    Check("long frame uses the same bounded step", Near(StepFlight(idle, forward, 1.3f), Vec3(420, 0, 0)));
    Check("frame partition preserves steady thrust", Near(Simulate(idle, forward, .25f, 17), Simulate(idle, forward, .25f, 33)));
    Check("negative or zero delta time does not move velocity",
        Near(StepFlight(Vec3(804, -251, 21), forward, -.1f), Vec3(804, -251, 21)) &&
        Near(StepFlight(Vec3(804, -251, 21), forward, 0), Vec3(804, -251, 21)));

    const Vec3 cruising = Simulate(idle, diagonal, 2.0f, 132);
    Check("diagonal cruise respects the 2200 SU/s cap", Near(cruising, diagonal * 2200.0f));
    const Vec3 coasting = Simulate(cruising, idle, 1.0f, 66);
    Check("throttle release keeps drift direction without gravity", Near(coasting, cruising * std::exp(-.52f), .01f));
    Check("coasting is independent of tick subdivision", Near(coasting, Simulate(cruising, idle, 1.0f, 128), .015f));
    Check("counter-thrust first brakes, then reverses",
        Near(StepFlight(Vec3(600, 0, 0), forward * -1, .1f), Vec3(180, 0, 0)) &&
        Near(Simulate(Vec3(600, 0, 0), forward * -1, .2f, 2), Vec3(-240, 0, 0)));

    const Vec3 previous(1430, -216, 180);
    const Vec3 redirected = StepFlight(previous, Vec3(0, 0, 1), .02f);
    Check("changing thrust axis preserves inertia", Length(redirected - previous) <= 84.005f && redirected.z > previous.z);

    std::cout << passed << " passed, " << failed << " failed\n";
    return failed == 0 ? 0 : 1;
}
