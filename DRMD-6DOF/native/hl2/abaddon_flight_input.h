#ifndef ABADDON_FLIGHT_INPUT_H
#define ABADDON_FLIGHT_INPUT_H

#include "c_basehlplayer.h"

inline bool AbaddonFlightInputActive()
{
    C_BaseHLPlayer *pilot = dynamic_cast<C_BaseHLPlayer *>(C_BasePlayer::GetLocalPlayer());
    return pilot && pilot->IsAbaddonFlightEnabled() && pilot->IsAlive() && !pilot->IsInAVehicle() &&
        !pilot->IsObserver() && !pilot->GetMoveParent() && pilot->GetMoveType() == MOVETYPE_WALK &&
        !(pilot->GetFlags() & (FL_FROZEN | FL_ONTRAIN));
}

inline void AbaddonApplyLocalLook(QAngle& angles, float pitch, float yaw, float roll)
{
    if (pitch == 0.0f && yaw == 0.0f && roll == 0.0f)
        return;
    matrix3x4_t body, delta, result;
    AngleMatrix(angles, body);
    AngleMatrix(QAngle(pitch, yaw, roll), delta);
    ConcatTransforms(body, delta, result);
    MatrixAngles(result, angles);
}

#endif
