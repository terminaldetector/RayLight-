#ifndef ABADDON_FLIGHT_MATH_H
#define ABADDON_FLIGHT_MATH_H

#include <cmath>

namespace abaddon
{
struct Vec3
{
    float x, y, z;

    explicit Vec3(float xValue = 0, float yValue = 0, float zValue = 0)
        : x(xValue), y(yValue), z(zValue) {}

    Vec3 operator+(const Vec3& other) const
    {
        return Vec3(x + other.x, y + other.y, z + other.z);
    }

    Vec3 operator-(const Vec3& other) const
    {
        return Vec3(x - other.x, y - other.y, z - other.z);
    }

    Vec3 operator*(float scale) const
    {
        return Vec3(x * scale, y * scale, z * scale);
    }

    float LengthSquared() const { return x * x + y * y + z * z; }
};

struct FlightBasis
{
    Vec3 forward, right, up;
};

inline Vec3 LimitLength(const Vec3& value, float limit)
{
    const float lengthSquared = value.LengthSquared();
    if (lengthSquared <= limit * limit)
        return value;

    return value * (limit / std::sqrt(lengthSquared));
}

inline Vec3 FlightWish(const FlightBasis& basis, float forward, float side, float lift)
{
    return LimitLength(basis.forward * forward + basis.right * side + basis.up * lift, 1.0f);
}

inline Vec3 StepFlight(const Vec3& velocity, const Vec3& wish, float seconds)
{
    const float acceleration = 4200.0f;
    const float maxSpeed = 2200.0f;
    const float coastDrag = 0.52f;

    if (seconds <= 0.0f)
        return velocity;
    if (seconds > 0.1f)
        seconds = 0.1f;

    if (wish.LengthSquared() < 0.000001f)
        return LimitLength(velocity * std::exp(-coastDrag * seconds), maxSpeed);

    const Vec3 target = LimitLength(wish, 1.0f) * maxSpeed;
    return LimitLength(velocity + LimitLength(target - velocity, acceleration * seconds), maxSpeed);
}
}  // namespace abaddon

#endif
