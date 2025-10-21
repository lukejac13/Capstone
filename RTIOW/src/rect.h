#ifndef RECT_H
#define RECT_H

#include <memory>
#include "hittable.h"
#include "material.h"

using std::shared_ptr;

// XY Rectangle (perpendicular to Z axis)
class xy_rect : public hittable {
public:
    xy_rect() {}
    xy_rect(double x0, double x1, double y0, double y1, double k, shared_ptr<material> mat) 
        : x0(x0), x1(x1), y0(y0), y1(y1), k(k), mat(mat) {}

    bool hit(const ray& r, interval ray_t, hit_record& rec) const override {
        // Ray equation: P(t) = A + t*b
        // For XY plane at z=k: k = A.z + t*b.z
        // Solve for t: t = (k - A.z) / b.z
        
        auto t = (k - r.origin().z()) / r.direction().z();
        
        if (!ray_t.contains(t))
            return false;
            
        auto x = r.origin().x() + t * r.direction().x();
        auto y = r.origin().y() + t * r.direction().y();
        
        if (x < x0 || x > x1 || y < y0 || y > y1)
            return false;
            
        rec.t = t;
        rec.p = r.at(t);
        rec.mat = mat;
        
        // Normal points in +Z direction
        vec3 outward_normal = vec3(0, 0, 1);
        rec.set_face_normal(r, outward_normal);
        
        return true;
    }

private:
    double x0, x1, y0, y1, k;  // Rectangle bounds and Z position
    shared_ptr<material> mat;
};

// XZ Rectangle (perpendicular to Y axis)
class xz_rect : public hittable {
public:
    xz_rect() {}
    xz_rect(double x0, double x1, double z0, double z1, double k, shared_ptr<material> mat)
        : x0(x0), x1(x1), z0(z0), z1(z1), k(k), mat(mat) {}

    bool hit(const ray& r, interval ray_t, hit_record& rec) const override {
        auto t = (k - r.origin().y()) / r.direction().y();
        
        if (!ray_t.contains(t))
            return false;
            
        auto x = r.origin().x() + t * r.direction().x();
        auto z = r.origin().z() + t * r.direction().z();
        
        if (x < x0 || x > x1 || z < z0 || z > z1)
            return false;
            
        rec.t = t;
        rec.p = r.at(t);
        rec.mat = mat;
        
        // Normal points in +Y direction
        vec3 outward_normal = vec3(0, 1, 0);
        rec.set_face_normal(r, outward_normal);
        
        return true;
    }

private:
    double x0, x1, z0, z1, k;  // Rectangle bounds and Y position
    shared_ptr<material> mat; 
};

// YZ Rectangle (perpendicular to X axis)
class yz_rect : public hittable {
public:
    yz_rect() {}
    yz_rect(double y0, double y1, double z0, double z1, double k, shared_ptr<material> mat)
        : y0(y0), y1(y1), z0(z0), z1(z1), k(k), mat(mat) {}

    bool hit(const ray& r, interval ray_t, hit_record& rec) const override {
        auto t = (k - r.origin().x()) / r.direction().x();
        
        if (!ray_t.contains(t))
            return false;
            
        auto y = r.origin().y() + t * r.direction().y();
        auto z = r.origin().z() + t * r.direction().z();
        
        if (y < y0 || y > y1 || z < z0 || z > z1)
            return false;
            
        rec.t = t;
        rec.p = r.at(t);
        rec.mat = mat;
        
        // Normal points in +X direction
        vec3 outward_normal = vec3(1, 0, 0);
        rec.set_face_normal(r, outward_normal);
        
        return true;
    }

private:
    double y0, y1, z0, z1, k;  // Rectangle bounds and X position
    shared_ptr<material> mat;
};

#endif