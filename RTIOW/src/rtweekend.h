#ifndef RTWEEKEND_H
#define RTWEEKEND_H

#include <cmath>
#include <iostream>
#include <limits>
#include <memory>
#include <random>

// C++ Std Usings

using std::make_shared;
using std::shared_ptr;

// Constants

const double infinity = std::numeric_limits<double>::infinity();
const double pi = 3.1415926535897932385;

// Utility Functions

inline double degrees_to_radians(double degrees) {
    return degrees * pi / 180.0;
}

inline double random_double() {
    // Thread-safe random number generation
    thread_local static std::random_device rd;
    thread_local static std::mt19937 gen(rd());
    thread_local static std::uniform_real_distribution<double> dis(0.0, 1.0);
    return dis(gen);
}

inline double random_double(double min, double max) {
    return min + (max - min) * random_double();
}

// Common Headers

#include "color.h"
#include "interval.h"
#include "ray.h"
#include "vec3.h"


#endif