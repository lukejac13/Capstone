#ifndef BOX_H
#define BOX_H

#include "hittable.h"
#include "hittable_list.h"
#include "rect.h"
#include "material.h"
#include <memory>

class box : public hittable {
public:
    box() {}
    box(const point3& p0, const point3& p1, shared_ptr<material> mat);

    bool hit(const ray& r, interval ray_t, hit_record& rec) const override {
        return sides.hit(r, ray_t, rec);
    }

private:
    point3 box_min;
    point3 box_max;
    hittable_list sides;
};

box::box(const point3& p0, const point3& p1, shared_ptr<material> mat) {
    box_min = p0;
    box_max = p1;

    // Create the 6 sides of the box
    sides.add(std::make_shared<xy_rect>(p0.x(), p1.x(), p0.y(), p1.y(), p1.z(), mat)); // Front
    sides.add(std::make_shared<xy_rect>(p0.x(), p1.x(), p0.y(), p1.y(), p0.z(), mat)); // Back
    
    sides.add(std::make_shared<xz_rect>(p0.x(), p1.x(), p0.z(), p1.z(), p1.y(), mat)); // Top
    sides.add(std::make_shared<xz_rect>(p0.x(), p1.x(), p0.z(), p1.z(), p0.y(), mat)); // Bottom
    
    sides.add(std::make_shared<yz_rect>(p0.y(), p1.y(), p0.z(), p1.z(), p1.x(), mat)); // Right
    sides.add(std::make_shared<yz_rect>(p0.y(), p1.y(), p0.z(), p1.z(), p0.x(), mat)); // Left
}

#endif