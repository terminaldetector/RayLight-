#include <math.h>

/* The old Valve library objects request the finite-input variants from glibc. */
double __pow_finite(double x, double y) { return pow(x, y); }
float __powf_finite(float x, float y) { return powf(x, y); }
double __atan2_finite(double y, double x) { return atan2(y, x); }
float __atan2f_finite(float y, float x) { return atan2f(y, x); }
double __log_finite(double x) { return log(x); }
float __logf_finite(float x) { return logf(x); }
double __acos_finite(double x) { return acos(x); }
float __acosf_finite(float x) { return acosf(x); }
double __asin_finite(double x) { return asin(x); }
float __asinf_finite(float x) { return asinf(x); }
double __exp_finite(double x) { return exp(x); }
float __expf_finite(float x) { return expf(x); }
