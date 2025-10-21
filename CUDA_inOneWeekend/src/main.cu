#include "rtweekend.h"

#include <chrono>
#include <iostream>

#include "camera.h"
#include "hittable.h"
#include "hittable_list.h"
#include "material.h"
#include "sphere.h"
#include "rect.h"
#include "box.h"




int main() {
    hittable_list world;

    // Create the ground/street
    auto street_material = make_shared<lambertian>(color(0.3, 0.3, 0.3));
    world.add(make_shared<sphere>(point3(0,-1000,0), 1000, street_material));

    // Define some materials for different building types
    auto concrete_material = make_shared<lambertian>(color(0.6, 0.6, 0.6));
    auto brick_material = make_shared<lambertian>(color(0.7, 0.4, 0.3));
    auto glass_material = make_shared<dielectric>(1.5);
    auto metal_material = make_shared<metal>(color(0.8, 0.8, 0.9), 0.1);
    auto blue_building = make_shared<metal>(color(0.2, 0.4, 0.8), 0.1);
    auto red_building = make_shared<lambertian>(color(0.8, 0.3, 0.2));
    auto green_building = make_shared<metal>(color(0.3, 0.7, 0.4), 0.1);

    // Create a city grid of buildings
    
    // Skyscraper 1 - Tall glass tower
    world.add(make_shared<box>(point3(-8, 0, -8), point3(-6, 12, -6), glass_material));
    
    // Skyscraper 2 - Metal and concrete tower
    world.add(make_shared<box>(point3(6, 0, -8), point3(8, 15, -6), metal_material));
    
    // Skyscraper 3 - Very tall center building
    world.add(make_shared<box>(point3(-1, 0, -1), point3(1, 18, 1), concrete_material));
    
    // Medium height buildings
    world.add(make_shared<box>(point3(-8, 0, 2), point3(-6, 8, 4), brick_material));
    world.add(make_shared<box>(point3(-4, 0, -8), point3(-2, 6, -6), blue_building));
    world.add(make_shared<box>(point3(2, 0, -8), point3(4, 7, -6), red_building));
    world.add(make_shared<box>(point3(6, 0, 2), point3(8, 9, 4), green_building));
    world.add(make_shared<box>(point3(-8, 0, 6), point3(-6, 5, 8), concrete_material));
    
    // Low-rise buildings
    world.add(make_shared<box>(point3(-4, 0, 2), point3(-2, 4, 4), brick_material));
    world.add(make_shared<box>(point3(2, 0, 2), point3(4, 3, 4), blue_building));
    world.add(make_shared<box>(point3(-4, 0, 6), point3(-2, 4, 8), red_building));
    world.add(make_shared<box>(point3(2, 0, 6), point3(4, 5, 8), green_building));
    
    // Create some stepped buildings (more complex structures)
    // Building with setbacks
    world.add(make_shared<box>(point3(-12, 0, -4), point3(-10, 8, -2), concrete_material));
    world.add(make_shared<box>(point3(-11.5, 8, -3.5), point3(-10.5, 12, -2.5), concrete_material));
    world.add(make_shared<box>(point3(-11.25, 12, -3.25), point3(-10.75, 15, -2.75), concrete_material));
    
    // L-shaped building
    world.add(make_shared<box>(point3(10, 0, -4), point3(12, 6, -2), brick_material));
    world.add(make_shared<box>(point3(10, 0, -2), point3(14, 6, 0), brick_material));
    
    // Add some architectural details - rooftop structures
    world.add(make_shared<box>(point3(-0.5, 18, -0.5), point3(0.5, 20, 0.5), metal_material)); // Antenna/spire
    world.add(make_shared<box>(point3(6.5, 15, -7.5), point3(7.5, 17, -6.5), glass_material)); // Rooftop structure
    
    // Add glass windows to all buildings
    auto window_glass = make_shared<dielectric>(1.5);
    
    // Windows for Skyscraper 1 (Glass tower at -8 to -6, height 12)
    // Since it's already glass, add some window frames with metal
    auto window_frame = make_shared<metal>(color(0.3, 0.3, 0.3), 0.0);
    for (int floor = 1; floor < 12; floor += 2) {
        // Front face windows
        world.add(make_shared<yz_rect>(floor, floor + 1.5, -7.8, -6.2, -8.01, window_glass));
        // Back face windows  
        world.add(make_shared<yz_rect>(floor, floor + 1.5, -7.8, -6.2, -5.99, window_glass));
        // Side face windows
        world.add(make_shared<xy_rect>(-7.8, -6.2, floor, floor + 1.5, -8.01, window_glass));
        world.add(make_shared<xy_rect>(-7.8, -6.2, floor, floor + 1.5, -5.99, window_glass));
    }
    
    // Windows for Skyscraper 2 (Metal tower at 6 to 8, height 15)
    for (int floor = 1; floor < 15; floor += 2) {
        // Front face windows
        world.add(make_shared<yz_rect>(floor, floor + 1.5, -7.8, -6.2, 5.99, window_glass));
        // Back face windows
        world.add(make_shared<yz_rect>(floor, floor + 1.5, -7.8, -6.2, 8.01, window_glass));
        // Side face windows
        world.add(make_shared<xy_rect>(6.2, 7.8, floor, floor + 1.5, -8.01, window_glass));
        world.add(make_shared<xy_rect>(6.2, 7.8, floor, floor + 1.5, -5.99, window_glass));
    }
    
    // Windows for Skyscraper 3 (Central tower at -1 to 1, height 18)
    for (int floor = 1; floor < 18; floor += 2) {
        // Front face windows
        world.add(make_shared<yz_rect>(floor, floor + 1.5, -0.8, 0.8, -1.01, window_glass));
        // Back face windows
        world.add(make_shared<yz_rect>(floor, floor + 1.5, -0.8, 0.8, 1.01, window_glass));
        // Side face windows
        world.add(make_shared<xy_rect>(-0.8, 0.8, floor, floor + 1.5, -1.01, window_glass));
        world.add(make_shared<xy_rect>(-0.8, 0.8, floor, floor + 1.5, 1.01, window_glass));
    }
    
    // Windows for medium height buildings
    // Building at (-8, 0, 2) to (-6, 8, 4) - brick material
    for (int floor = 1; floor < 8; floor += 2) {
        world.add(make_shared<yz_rect>(floor, floor + 1.5, 2.2, 3.8, -8.01, window_glass));
        world.add(make_shared<yz_rect>(floor, floor + 1.5, 2.2, 3.8, -5.99, window_glass));
        world.add(make_shared<xy_rect>(-7.8, -6.2, floor, floor + 1.5, 1.99, window_glass));
        world.add(make_shared<xy_rect>(-7.8, -6.2, floor, floor + 1.5, 4.01, window_glass));
    }
    
    // Building at (-4, 0, -8) to (-2, 6, -6) - blue building
    for (int floor = 1; floor < 6; floor += 2) {
        world.add(make_shared<yz_rect>(floor, floor + 1.5, -7.8, -6.2, -4.01, window_glass));
        world.add(make_shared<yz_rect>(floor, floor + 1.5, -7.8, -6.2, -1.99, window_glass));
        world.add(make_shared<xy_rect>(-3.8, -2.2, floor, floor + 1.5, -8.01, window_glass));
        world.add(make_shared<xy_rect>(-3.8, -2.2, floor, floor + 1.5, -5.99, window_glass));
    }
    
    // Building at (2, 0, -8) to (4, 7, -6) - red building
    for (int floor = 1; floor < 7; floor += 2) {
        world.add(make_shared<yz_rect>(floor, floor + 1.5, -7.8, -6.2, 1.99, window_glass));
        world.add(make_shared<yz_rect>(floor, floor + 1.5, -7.8, -6.2, 4.01, window_glass));
        world.add(make_shared<xy_rect>(2.2, 3.8, floor, floor + 1.5, -8.01, window_glass));
        world.add(make_shared<xy_rect>(2.2, 3.8, floor, floor + 1.5, -5.99, window_glass));
    }
    
    // Building at (6, 0, 2) to (8, 9, 4) - green building
    for (int floor = 1; floor < 9; floor += 2) {
        world.add(make_shared<yz_rect>(floor, floor + 1.5, 2.2, 3.8, 5.99, window_glass));
        world.add(make_shared<yz_rect>(floor, floor + 1.5, 2.2, 3.8, 8.01, window_glass));
        world.add(make_shared<xy_rect>(6.2, 7.8, floor, floor + 1.5, 1.99, window_glass));
        world.add(make_shared<xy_rect>(6.2, 7.8, floor, floor + 1.5, 4.01, window_glass));
    }
    
    // Building at (-8, 0, 6) to (-6, 5, 8) - concrete
    for (int floor = 1; floor < 5; floor += 2) {
        world.add(make_shared<yz_rect>(floor, floor + 1.5, 6.2, 7.8, -8.01, window_glass));
        world.add(make_shared<yz_rect>(floor, floor + 1.5, 6.2, 7.8, -5.99, window_glass));
        world.add(make_shared<xy_rect>(-7.8, -6.2, floor, floor + 1.5, 5.99, window_glass));
        world.add(make_shared<xy_rect>(-7.8, -6.2, floor, floor + 1.5, 8.01, window_glass));
    }
    
    // Windows for low-rise buildings
    // Building at (-4, 0, 2) to (-2, 4, 4) - brick
    for (int floor = 1; floor < 4; floor += 2) {
        world.add(make_shared<yz_rect>(floor, floor + 1.5, 2.2, 3.8, -4.01, window_glass));
        world.add(make_shared<yz_rect>(floor, floor + 1.5, 2.2, 3.8, -1.99, window_glass));
        world.add(make_shared<xy_rect>(-3.8, -2.2, floor, floor + 1.5, 1.99, window_glass));
        world.add(make_shared<xy_rect>(-3.8, -2.2, floor, floor + 1.5, 4.01, window_glass));
    }
    
    // Building at (2, 0, 2) to (4, 3, 4) - blue
    for (int floor = 1; floor < 3; floor += 2) {
        world.add(make_shared<yz_rect>(floor, floor + 1.5, 2.2, 3.8, 1.99, window_glass));
        world.add(make_shared<yz_rect>(floor, floor + 1.5, 2.2, 3.8, 4.01, window_glass));
        world.add(make_shared<xy_rect>(2.2, 3.8, floor, floor + 1.5, 1.99, window_glass));
        world.add(make_shared<xy_rect>(2.2, 3.8, floor, floor + 1.5, 4.01, window_glass));
    }
    
    // Building at (-4, 0, 6) to (-2, 4, 8) - red
    for (int floor = 1; floor < 4; floor += 2) {
        world.add(make_shared<yz_rect>(floor, floor + 1.5, 6.2, 7.8, -4.01, window_glass));
        world.add(make_shared<yz_rect>(floor, floor + 1.5, 6.2, 7.8, -1.99, window_glass));
        world.add(make_shared<xy_rect>(-3.8, -2.2, floor, floor + 1.5, 5.99, window_glass));
        world.add(make_shared<xy_rect>(-3.8, -2.2, floor, floor + 1.5, 8.01, window_glass));
    }
    
    // Building at (2, 0, 6) to (4, 5, 8) - green
    for (int floor = 1; floor < 5; floor += 2) {
        world.add(make_shared<yz_rect>(floor, floor + 1.5, 6.2, 7.8, 1.99, window_glass));
        world.add(make_shared<yz_rect>(floor, floor + 1.5, 6.2, 7.8, 4.01, window_glass));
        world.add(make_shared<xy_rect>(2.2, 3.8, floor, floor + 1.5, 5.99, window_glass));
        world.add(make_shared<xy_rect>(2.2, 3.8, floor, floor + 1.5, 8.01, window_glass));
    }
    
    // Windows for stepped building (-12, 0, -4) to (-10, 8, -2)
    for (int floor = 1; floor < 8; floor += 2) {
        world.add(make_shared<yz_rect>(floor, floor + 1.5, -3.8, -2.2, -12.01, window_glass));
        world.add(make_shared<yz_rect>(floor, floor + 1.5, -3.8, -2.2, -9.99, window_glass));
        world.add(make_shared<xy_rect>(-11.8, -10.2, floor, floor + 1.5, -4.01, window_glass));
        world.add(make_shared<xy_rect>(-11.8, -10.2, floor, floor + 1.5, -1.99, window_glass));
    }
    
    // Windows for L-shaped building part 1: (10, 0, -4) to (12, 6, -2)
    for (int floor = 1; floor < 6; floor += 2) {
        world.add(make_shared<yz_rect>(floor, floor + 1.5, -3.8, -2.2, 9.99, window_glass));
        world.add(make_shared<yz_rect>(floor, floor + 1.5, -3.8, -2.2, 12.01, window_glass));
        world.add(make_shared<xy_rect>(10.2, 11.8, floor, floor + 1.5, -4.01, window_glass));
        world.add(make_shared<xy_rect>(10.2, 11.8, floor, floor + 1.5, -1.99, window_glass));
    }
    
    // Windows for L-shaped building part 2: (10, 0, -2) to (14, 6, 0)
    for (int floor = 1; floor < 6; floor += 2) {
        world.add(make_shared<yz_rect>(floor, floor + 1.5, -1.8, -0.2, 9.99, window_glass));
        world.add(make_shared<yz_rect>(floor, floor + 1.5, -1.8, -0.2, 14.01, window_glass));
        world.add(make_shared<xy_rect>(10.2, 13.8, floor, floor + 1.5, -2.01, window_glass));
        world.add(make_shared<xy_rect>(10.2, 13.8, floor, floor + 1.5, 0.01, window_glass));
    }
    
    // Create roads/streets using rectangles
    auto road_material = make_shared<lambertian>(color(0.2, 0.2, 0.2));
    
    // Main street running north-south
    world.add(make_shared<xz_rect>(-0.5, 0.5, -15, 15, 0.01, road_material));
    
    // Cross street running east-west
    world.add(make_shared<xz_rect>(-15, 15, -0.5, 0.5, 0.01, road_material));
    
    // Add some smaller streets
    world.add(make_shared<xz_rect>(-5.5, -4.5, -15, 15, 0.01, road_material));
    world.add(make_shared<xz_rect>(4.5, 5.5, -15, 15, 0.01, road_material));
    world.add(make_shared<xz_rect>(-15, 15, -5.5, -4.5, 0.01, road_material));
    world.add(make_shared<xz_rect>(-15, 15, 4.5, 5.5, 0.01, road_material));
    
    // Add some decorative elements - floating glass panels (like billboards)
    auto billboard_material = make_shared<dielectric>(1.3);
    world.add(make_shared<yz_rect>(5, 7, -3, -1, -9, billboard_material));
    world.add(make_shared<xy_rect>(-3, -1, 8, 10, 9, billboard_material));
    
    // Add some spherical elements (could be decorative or water towers)
    auto water_tower = make_shared<metal>(color(0.7, 0.7, 0.8), 0.2);
    world.add(make_shared<sphere>(point3(-7, 13, -7), 0.8, water_tower));
    world.add(make_shared<sphere>(point3(7, 16, -7), 0.6, water_tower));
    
    // Decorative spheres (like sculptures or lights)
    auto decoration = make_shared<lambertian>(color(1.0, 0.8, 0.2));
    world.add(make_shared<sphere>(point3(0, 2, 0), 0.3, decoration));
    world.add(make_shared<sphere>(point3(-5, 1, 0), 0.2, decoration));
    world.add(make_shared<sphere>(point3(5, 1, 0), 0.2, decoration));

    camera cam;

    cam.aspect_ratio      = 16.0 / 9.0;
    cam.image_width       = 1200;
    cam.samples_per_pixel = 100;  // Good balance of quality and speed
    cam.max_depth         = 50;

    cam.vfov     = 45;  // Wider field of view to capture more of the city
    cam.lookfrom = point3(20, 20, 10);  // Elevated position to see the city
    cam.lookat   = point3(0, 8, 0);     // Look towards center of city
    cam.vup      = vec3(0,1,0);

    cam.defocus_angle = 0.2;  // Sharp focus for architectural details
    cam.focus_dist    = 25.0;




    // Start timing
    auto start_time = std::chrono::high_resolution_clock::now();


    //Main render call
    cam.render(world); 
    


    // Stop timing and calculate elapsed time
    auto end_time = std::chrono::high_resolution_clock::now();
    auto duration = std::chrono::duration_cast<std::chrono::milliseconds>(end_time - start_time);
    std::cerr << "Rendering completed in " << duration.count() / 1000.0 << " seconds" << std::endl;
}
