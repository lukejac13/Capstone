#ifndef TRIANGLEH
#define TRIANGLEH

#include "hitable.h"

class triangle: public hitable {
    public:
        __device__ triangle() {}
        __device__ triangle(const vec3& a, const vec3& b, const vec3& c, material *m) : v0(a), v1(b), v2(c), mat_ptr(m) {}
        __device__ virtual bool hit(const ray& r, float t_min, float t_max, hit_record& rec) const;
        __device__ virtual ~triangle() { delete mat_ptr; }

        vec3 v0;
        vec3 v1;
        vec3 v2;
        material *mat_ptr;
};

__device__ bool triangle::hit(const ray& r, float t_min, float t_max, hit_record& rec) const {
    const float EPSILON = 1e-6f;
    vec3 edge1 = v1 - v0;
    vec3 edge2 = v2 - v0;
    vec3 pvec = cross(r.direction(), edge2);
    float det = dot(edge1, pvec);
    if (det > -EPSILON && det < EPSILON) return false; // ray parallel to triangle
    float inv_det = 1.0f / det;
    vec3 tvec = r.origin() - v0;
    float u = dot(tvec, pvec) * inv_det;
    if (u < 0.0f || u > 1.0f) return false;
    vec3 qvec = cross(tvec, edge1);
    float v = dot(r.direction(), qvec) * inv_det;
    if (v < 0.0f || u + v > 1.0f) return false;
    float t = dot(edge2, qvec) * inv_det;
    if (t < t_min || t > t_max) return false;

    rec.t = t;
    rec.p = r.point_at_parameter(t);
    vec3 n = unit_vector(cross(edge1, edge2));
    // Ensure normal faces against the ray
    if (dot(r.direction(), n) > 0.0f) n = -n;
    rec.normal = n;
    rec.mat_ptr = mat_ptr;
    return true;
}

#endif
