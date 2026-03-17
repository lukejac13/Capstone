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

// Mesh-based hitable to avoid per-triangle device allocation for large OBJ scenes
class mesh : public hitable {
public:
    __device__ mesh(vec3 *verts, int *inds, int num_inds, material *m)
        : vertices(verts), indices(inds), num_indices(num_inds), mat_ptr(m) {}
    __device__ virtual bool hit(const ray& r, float t_min, float t_max, hit_record& rec) const {
        hit_record temp_rec;
        bool hit_anything = false;
        float closest_so_far = t_max;
        int triangle_count = num_indices / 3;

        for (int i = 0; i < triangle_count; i++) {
            int idx0 = indices[i*3 + 0];
            int idx1 = indices[i*3 + 1];
            int idx2 = indices[i*3 + 2];
            vec3 v0 = vertices[idx0];
            vec3 v1 = vertices[idx1];
            vec3 v2 = vertices[idx2];

            // manual triangle intersection
            const float EPSILON = 1e-6f;
            vec3 edge1 = v1 - v0;
            vec3 edge2 = v2 - v0;
            vec3 pvec = cross(r.direction(), edge2);
            float det = dot(edge1, pvec);
            if (det > -EPSILON && det < EPSILON) continue;
            float inv_det = 1.0f / det;
            vec3 tvec = r.origin() - v0;
            float u = dot(tvec, pvec) * inv_det;
            if (u < 0.0f || u > 1.0f) continue;
            vec3 qvec = cross(tvec, edge1);
            float v = dot(r.direction(), qvec) * inv_det;
            if (v < 0.0f || u + v > 1.0f) continue;
            float t = dot(edge2, qvec) * inv_det;
            if (t <= t_min || t >= closest_so_far) continue;

            closest_so_far = t;
            temp_rec.t = t;
            temp_rec.p = r.point_at_parameter(t);
            vec3 n = unit_vector(cross(edge1, edge2));
            if (dot(r.direction(), n) > 0.0f) n = -n;
            temp_rec.normal = n;
            temp_rec.mat_ptr = mat_ptr;
            hit_anything = true;
        }

        if (hit_anything) {
            rec = temp_rec;
        }
        return hit_anything;
    }

    __device__ virtual ~mesh() { if (mat_ptr) delete mat_ptr; }

    vec3 *vertices;
    int *indices;
    int num_indices;
    material *mat_ptr;
};

#endif
