#include "../abaddon_recovery.h"
#include <cmath>
#include <cstdio>

static int failures;

static void Check(bool condition, const char *name)
{
    std::printf("%s | %s\n", condition ? "PASS" : "FAIL", name);
    if (!condition) ++failures;
}

int main()
{
    using namespace abaddon;
    const RecoveryAmount crate = {22,12,9};
    const RecoveryAmount tick = {5,2,1};
    Check(!FitRecovery(crate,100,100,100,100).Any(), "full pilot leaves cloud available");
    Check(!FitRecovery(crate,110,112,100,120).Any(), "overcharged values preserved");
    RecoveryAmount g = FitRecovery(crate,90,100,100,100);
    Check(g.Any() && g.energy==10 && g.hull==0 && g.armor==0, "partial energy only");
    g = FitRecovery(crate,100,40,100,100);
    Check(g.energy==0 && g.hull==12 && g.armor==0, "full energy still permits hull repair");
    g = FitRecovery(crate,100,100,100,93);
    Check(g.energy==0 && g.hull==0 && g.armor==7, "armor-only salvage");
    g = FitRecovery(crate,0,48,50,0);
    Check(g.energy==22 && g.hull==2 && g.armor==9, "custom health maximum respected");
    g = FitRecovery(tick,98.5f,99,100,99);
    Check(g.energy==1.5f && g.hull==1 && g.armor==1, "station caps all resources independently");
    g = FitRecovery(tick,0,55,100,2);
    Check(g.energy==5 && g.hull==2 && g.armor==1, "service pulse");
    g = DroneSalvage(25);
    Check(g.energy==11 && g.hull==7 && g.armor==9, "small drone reward");
    g = DroneSalvage(220);
    Check(g.energy==18 && g.hull==12 && g.armor==9, "reference drone reward");
    g = DroneSalvage(2200);
    Check(g.energy==41 && g.hull==27, "heavy reward capped");
    Check(CloudOpacity(13)==1 && CloudOpacity(3)==1, "stable visible lifetime");
    Check(std::fabs(CloudOpacity(.85f)-.5f)<.0001f, "transparent fade midpoint");
    Check(CloudOpacity(0)==0 && CloudOpacity(-.01f)==0, "expired cloud invisible");
    return failures ? 1 : 0;
}
