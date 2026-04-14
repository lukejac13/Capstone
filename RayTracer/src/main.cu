#include <iostream>
#include <fstream>
#include <time.h>
#include <float.h>
#include <curand_kernel.h>
#include <string>
#include <algorithm>
#include <cctype>
#include <io.h>
#include <sys/stat.h>
#include "vec3.h"
#include "ray.h"
#include "sphere.h"
#include "triangle.h"
#include "hitable_list.h"
#include "camera.h"
#include "material.h"
#include "obj_loader.h"
#define STB_IMAGE_IMPLEMENTATION
#include "stb_image.h"

// limited version of checkCudaErrors from helper_cuda.h in CUDA examples
#define checkCudaErrors(val) check_cuda( (val), #val, __FILE__, __LINE__ )

void check_cuda(cudaError_t result, char const *const func, const char *const file, int const line) {
    if (result) {
        std::cerr << "CUDA error = " << static_cast<unsigned int>(result) << " at " <<
            file << ":" << line << " '" << func << "' \n";
        // Make sure we call CUDA Device Reset before exiting
        cudaDeviceReset();
        exit(99);
    }
}

static const char *camera_view_name(int option) {
    switch (option) {
        case 0: return "front";
        case 1: return "back";
        case 2: return "left";
        case 3: return "right";
        case 4: return "front-left";
        case 5: return "front-right";
        case 6: return "back-left";
        case 7: return "back-right";
        default: return "front";
    }
}

static std::string to_lower(std::string str) {
    std::transform(str.begin(), str.end(), str.begin(), [](unsigned char c) { return static_cast<char>(std::tolower(c)); });
    return str;
}

static bool is_integer(const std::string &s) {
    if (s.empty()) return false;
    for (unsigned char c : s) {
        if (!std::isdigit(c)) return false;
    }
    return true;
}

static int parse_camera_view_arg(const std::string &view_arg) {
    std::string value = to_lower(view_arg);
    if (value.empty()) return 0;
    if (value == "front") return 0;
    if (value == "back") return 1;
    if (value == "left") return 2;
    if (value == "right") return 3;
    if (value == "front-left" || value == "front_left" || value == "frontleft" || value == "fl") return 4;
    if (value == "front-right" || value == "front_right" || value == "fr") return 5;
    if (value == "back-left" || value == "back_left" || value == "backleft" || value == "bl") return 6;
    if (value == "back-right" || value == "back_right" || value == "backright" || value == "br") return 7;
    if (value.size() == 1 && std::isdigit(static_cast<unsigned char>(value[0]))) {
        int numeric = atoi(value.c_str());
        if (numeric >= 0 && numeric <= 7) return numeric;
    }
    return 0;
}

static bool is_directory(const std::string &path) {
    struct _stat info;
    if (_stat(path.c_str(), &info) != 0) return false;
    return (info.st_mode & _S_IFDIR) != 0;
}

static std::string find_obj_in_directory(const std::string &dir_path) {
    std::string dir = dir_path;
    if (!dir.empty() && dir.back() != '/' && dir.back() != '\\') {
        dir += "\\";
    }

    std::string search_path = dir + "*.obj";
    struct _finddata_t file_info;
    intptr_t handle = _findfirst(search_path.c_str(), &file_info);
    if (handle == -1) {
        return std::string();
    }

    std::string found;
    do {
        if ((file_info.attrib & _A_SUBDIR) == 0) {
            found = dir + file_info.name;
            break;
        }
    } while (_findnext(handle, &file_info) == 0);

    _findclose(handle);
    return found;
}

static void compute_camera_for_mesh(const Mesh &mesh, int camera_option, vec3 &lookfrom, vec3 &lookat, float &dist_to_focus) {
    if (mesh.vertices.empty()) {
        lookfrom = vec3(10000, 3000, 2000);
        lookat = vec3(0, 10, 0);
        dist_to_focus = (lookfrom - lookat).length();
        return;
    }

    vec3 minp(FLT_MAX, FLT_MAX, FLT_MAX);
    vec3 maxp(-FLT_MAX, -FLT_MAX, -FLT_MAX);
    for (size_t i = 0; i < mesh.vertices.size(); i++) {
        const vec3 &v = mesh.vertices[i];
        if (v.x() < minp.x()) minp[0] = v.x();
        if (v.y() < minp.y()) minp[1] = v.y();
        if (v.z() < minp.z()) minp[2] = v.z();
        if (v.x() > maxp.x()) maxp[0] = v.x();
        if (v.y() > maxp.y()) maxp[1] = v.y();
        if (v.z() > maxp.z()) maxp[2] = v.z();
    }

    lookat = (minp + maxp) * 0.5f;
    vec3 extents = maxp - minp;
    float radius = 0.5f * sqrt(extents.x()*extents.x() + extents.y()*extents.y() + extents.z()*extents.z());
    const float fov = 20.0f * 3.14159265358979323846f / 180.0f;
    float distance = radius / sinf(fov * 0.5f) * 1.15f;
    if (distance < radius * 2.0f) distance = radius * 2.0f;

    const vec3 directions[8] = {
        vec3(0.0f, 0.0f, 1.0f),
        vec3(0.0f, 0.0f, -1.0f),
        vec3(-1.0f, 0.0f, 0.0f),
        vec3(1.0f, 0.0f, 0.0f),
        vec3(-0.70710678f, 0.0f, 0.70710678f),
        vec3(0.70710678f, 0.0f, 0.70710678f),
        vec3(-0.70710678f, 0.0f, -0.70710678f),
        vec3(0.70710678f, 0.0f, -0.70710678f)
    };
    int option = camera_option % 8;
    if (option < 0) option = 0;
    vec3 direction = directions[option];

    lookfrom = lookat + vec3(direction.x(), 0.0f, direction.z()) * distance + vec3(0.0f, radius * 0.3f, 0.0f);
    dist_to_focus = (lookfrom - lookat).length();
}

// Matching the C++ code would recurse enough into color() calls that
// it was blowing up the stack, so we have to turn this into a
// limited-depth loop instead.  Later code in the book limits to a max
// depth of 50, so we adapt this a few chapters early on the GPU.
__device__ vec3 color(const ray& r, hitable **world, curandState *local_rand_state) {
    ray cur_ray = r;
    vec3 cur_attenuation = vec3(1.0,1.0,1.0);
    for(int i = 0; i < 50; i++) {
        hit_record rec;
        if ((*world)->hit(cur_ray, 0.001f, FLT_MAX, rec)) {
            ray scattered;
            vec3 attenuation;
            if(rec.mat_ptr->scatter(cur_ray, rec, attenuation, scattered, local_rand_state)) {
                cur_attenuation *= attenuation;
                cur_ray = scattered;
            }
            else {
                return vec3(0.0,0.0,0.0);
            }
        }
        else {
            vec3 unit_direction = unit_vector(cur_ray.direction());
            float t = 0.5f*(unit_direction.y() + 1.0f);
            vec3 c = (1.0f-t)*vec3(1.0, 1.0, 1.0) + t*vec3(0.5, 0.7, 1.0);
            return cur_attenuation * c;
        }
    }
    return vec3(0.0,0.0,0.0); // exceeded recursion
}

__global__ void rand_init(curandState *rand_state) {
    if (threadIdx.x == 0 && blockIdx.x == 0) {
        curand_init(1984, 0, 0, rand_state);
    }
}

__global__ void render_init(int max_x, int max_y, curandState *rand_state) {
    int i = threadIdx.x + blockIdx.x * blockDim.x;
    int j = threadIdx.y + blockIdx.y * blockDim.y;
    if((i >= max_x) || (j >= max_y)) return;
    int pixel_index = j*max_x + i;
    // Original: Each thread gets same seed, a different sequence number, no offset
    // curand_init(1984, pixel_index, 0, &rand_state[pixel_index]);
    // BUGFIX, see Issue#2: Each thread gets different seed, same sequence for
    // performance improvement of about 2x!
    curand_init(1984+pixel_index, 0, 0, &rand_state[pixel_index]);
}

__global__ void render(vec3 *fb, int max_x, int max_y, int ns, camera **cam, hitable **world, curandState *rand_state) {
    int i = threadIdx.x + blockIdx.x * blockDim.x;
    int j = threadIdx.y + blockIdx.y * blockDim.y;
    if((i >= max_x) || (j >= max_y)) return;
    int pixel_index = j*max_x + i;
    curandState local_rand_state = rand_state[pixel_index];
    vec3 col(0,0,0);
    for(int s=0; s < ns; s++) {
        float u = float(i + curand_uniform(&local_rand_state)) / float(max_x);
        float v = float(j + curand_uniform(&local_rand_state)) / float(max_y);
        ray r = (*cam)->get_ray(u, v, &local_rand_state);
        col += color(r, world, &local_rand_state);
    }
    rand_state[pixel_index] = local_rand_state;
    col /= float(ns);
    col[0] = sqrt(col[0]);
    col[1] = sqrt(col[1]);
    col[2] = sqrt(col[2]);
    fb[pixel_index] = col;
}

#define RND (curand_uniform(&local_rand_state))

__global__ void create_world(hitable **d_list, hitable **d_world, camera **d_camera, int nx, int ny, curandState *rand_state, 
                             vec3 *mesh_vertices, int *mesh_indices, int num_indices,
                             vec3 *mesh_texcoords, int *mesh_texcoord_indices, bool mesh_has_texcoords,
                             int *mesh_material_ids, vec3 *mesh_material_colors, material **mesh_materials, int num_mesh_materials,
                             unsigned char **material_texture_pixels, int *material_texture_widths, int *material_texture_heights, int *material_texture_channels,
                             vec3 lookfrom, vec3 lookat, float dist_to_focus, bool use_mesh) {
    if (threadIdx.x == 0 && blockIdx.x == 0) {
        // Create a ground (two large triangles) and a grid of small triangular prisms
        curandState local_rand_state = *rand_state;
        int i = 0;

        if (use_mesh && mesh_vertices != nullptr && mesh_indices != nullptr && num_indices > 0) {
            int num_triangles = num_indices / 3;
            printf("Using mesh acceleration: %d triangles in one hitable.\n", num_triangles);

            if (num_mesh_materials <= 0) {
                mesh_materials[0] = new lambertian(vec3(0.6f, 0.6f, 0.6f));
                num_mesh_materials = 1;
            } else {
                for (int m = 0; m < num_mesh_materials; m++) {
                    if (material_texture_pixels != nullptr && material_texture_pixels[m] != nullptr) {
                        mesh_materials[m] = new lambertian(material_texture_pixels[m], material_texture_widths[m], material_texture_heights[m], material_texture_channels[m]);
                    } else {
                        mesh_materials[m] = new lambertian(mesh_material_colors[m]);
                    }
                }
            }

            d_list[i++] = new mesh(mesh_vertices, mesh_indices, num_indices, mesh_material_ids, mesh_materials, num_mesh_materials, mesh_texcoords, mesh_texcoord_indices, mesh_has_texcoords);

            printf("Mesh hitable created.\n");
        } else {
            // Original hardcoded scene
            // Ground as two large triangles (each has its own material instance)
            d_list[i++] = new triangle(vec3(-1000.0f, -0.5f, -1000.0f), vec3(1000.0f, -0.5f, -1000.0f), vec3(1000.0f, -0.5f, 1000.0f), new lambertian(vec3(0.5f, 0.5f, 0.5f)));
            d_list[i++] = new triangle(vec3(-1000.0f, -0.5f, -1000.0f), vec3(1000.0f, -0.5f, 1000.0f), vec3(-1000.0f, -0.5f, 1000.0f), new lambertian(vec3(0.5f, 0.5f, 0.5f)));

            // Grid of small prisms/spheres replacing the old spheres
            for(int a = -11; a < 11; a++) {
                for(int b = -11; b < 11; b++) {
                    float shape_choice = RND; // decide prism vs sphere
                    float choose_mat = RND;   // decide material
                    vec3 center(a + RND, 0.2f, b + RND);
                    float s = 0.2f; // base size
                    float h = 0.2f; // extrusion height
                    if (shape_choice < 0.5f) {
                        // make a small sphere instead of a prism
                        if (choose_mat < 0.8f) {
                            d_list[i++] = new sphere(center, s, new lambertian(vec3(RND*RND, RND*RND, RND*RND)));
                        } else if (choose_mat < 0.95f) {
                            d_list[i++] = new sphere(center, s, new metal(vec3(0.5f*(1.0f+RND), 0.5f*(1.0f+RND), 0.5f*(1.0f+RND)), 0.5f*RND));
                        } else {
                            d_list[i++] = new sphere(center, s, new dielectric(1.5f));
                        }
                    } else {
                        // build a small triangular prism (6 triangles)
                        vec3 p0 = center + vec3(0.0f, 0.0f, -s);
                        vec3 p1 = center + vec3(s, 0.0f, -s);
                        vec3 p2 = center + vec3(s*0.5f, s*0.8660254f, -s);
                        vec3 q0 = p0 + vec3(0.0f, 0.0f, h);
                        vec3 q1 = p1 + vec3(0.0f, 0.0f, h);
                        vec3 q2 = p2 + vec3(0.0f, 0.0f, h);

                        if (choose_mat < 0.8f) {
                            d_list[i++] = new triangle(p0, p1, p2, new lambertian(vec3(RND*RND, RND*RND, RND*RND)));
                            d_list[i++] = new triangle(q0, q2, q1, new lambertian(vec3(RND*RND, RND*RND, RND*RND)));
                            d_list[i++] = new triangle(p0, p1, q1, new lambertian(vec3(RND*RND, RND*RND, RND*RND)));
                            d_list[i++] = new triangle(p0, q1, q0, new lambertian(vec3(RND*RND, RND*RND, RND*RND)));
                            d_list[i++] = new triangle(p1, p2, q2, new lambertian(vec3(RND*RND, RND*RND, RND*RND)));
                            d_list[i++] = new triangle(p1, q2, q1, new lambertian(vec3(RND*RND, RND*RND, RND*RND)));
                        } else if (choose_mat < 0.95f) {
                            d_list[i++] = new triangle(p0, p1, p2, new metal(vec3(0.5f*(1.0f+RND), 0.5f*(1.0f+RND), 0.5f*(1.0f+RND)), 0.5f*RND));
                            d_list[i++] = new triangle(q0, q2, q1, new metal(vec3(0.5f*(1.0f+RND), 0.5f*(1.0f+RND), 0.5f*(1.0f+RND)), 0.5f*RND));
                            d_list[i++] = new triangle(p0, p1, q1, new metal(vec3(0.5f*(1.0f+RND), 0.5f*(1.0f+RND), 0.5f*(1.0f+RND)), 0.5f*RND));
                            d_list[i++] = new triangle(p0, q1, q0, new metal(vec3(0.5f*(1.0f+RND), 0.5f*(1.0f+RND), 0.5f*(1.0f+RND)), 0.5f*RND));
                            d_list[i++] = new triangle(p1, p2, q2, new metal(vec3(0.5f*(1.0f+RND), 0.5f*(1.0f+RND), 0.5f*(1.0f+RND)), 0.5f*RND));
                            d_list[i++] = new triangle(p1, q2, q1, new metal(vec3(0.5f*(1.0f+RND), 0.5f*(1.0f+RND), 0.5f*(1.0f+RND)), 0.5f*RND));
                        } else {
                            d_list[i++] = new triangle(p0, p1, p2, new dielectric(1.5f));
                            d_list[i++] = new triangle(q0, q2, q1, new dielectric(1.5f));
                            d_list[i++] = new triangle(p0, p1, q1, new dielectric(1.5f));
                            d_list[i++] = new triangle(p0, q1, q0, new dielectric(1.5f));
                            d_list[i++] = new triangle(p1, p2, q2, new dielectric(1.5f));
                            d_list[i++] = new triangle(p1, q2, q1, new dielectric(1.5f));
                        }
                    }
                }
            }

            // Create three larger prisms in place of the previous big spheres
            // Create three larger prisms with randomized Y-rotation
            const float PI = 3.14159265358979323846f;

            // Big prism 1 (dielectric-like) with random rotation
            {
                vec3 ctr = vec3(5,1,-2);
                float S = 1.0f; float H = 1.0f;
                float theta = 2.0f*PI*RND; // random rotation
                float ct = cosf(theta), st = sinf(theta);
                vec3 p0 = ctr + vec3(0.0f, 0.0f, -S);
                vec3 p1 = ctr + vec3(S, 0.0f, -S);
                vec3 p2 = ctr + vec3(S*0.5f, S*0.8660254f, -S);
                vec3 q0 = p0 + vec3(0.0f, 0.0f, H);
                vec3 q1 = p1 + vec3(0.0f, 0.0f, H);
                vec3 q2 = p2 + vec3(0.0f, 0.0f, H);
                // rotate around Y about ctr
                {
                    vec3 r = p0 - ctr;
                    float rx = ct * r.x() + st * r.z();
                    float rz = -st * r.x() + ct * r.z();
                    p0 = vec3(rx + ctr.x(), r.y() + ctr.y(), rz + ctr.z());
                }
                {
                    vec3 r = p1 - ctr;
                    float rx = ct * r.x() + st * r.z();
                    float rz = -st * r.x() + ct * r.z();
                    p1 = vec3(rx + ctr.x(), r.y() + ctr.y(), rz + ctr.z());
                }
                {
                    vec3 r = p2 - ctr;
                    float rx = ct * r.x() + st * r.z();
                    float rz = -st * r.x() + ct * r.z();
                    p2 = vec3(rx + ctr.x(), r.y() + ctr.y(), rz + ctr.z());
                }
                {
                    vec3 r = q0 - ctr;
                    float rx = ct * r.x() + st * r.z();
                    float rz = -st * r.x() + ct * r.z();
                    q0 = vec3(rx + ctr.x(), r.y() + ctr.y(), rz + ctr.z());
                }
                {
                    vec3 r = q1 - ctr;
                    float rx = ct * r.x() + st * r.z();
                    float rz = -st * r.x() + ct * r.z();
                    q1 = vec3(rx + ctr.x(), r.y() + ctr.y(), rz + ctr.z());
                }
                {
                    vec3 r = q2 - ctr;
                    float rx = ct * r.x() + st * r.z();
                    float rz = -st * r.x() + ct * r.z();
                    q2 = vec3(rx + ctr.x(), r.y() + ctr.y(), rz + ctr.z());
                }
                d_list[i++] = new triangle(p0, p1, p2, new dielectric(1.5f));
                d_list[i++] = new triangle(q0, q2, q1, new dielectric(1.5f));
                d_list[i++] = new triangle(p0, p1, q1, new dielectric(1.5f));
                d_list[i++] = new triangle(p0, q1, q0, new dielectric(1.5f));
                d_list[i++] = new triangle(p1, p2, q2, new dielectric(1.5f));
                d_list[i++] = new triangle(p1, q2, q1, new dielectric(1.5f));
            }

            // Big prism 2 (lambertian) with random rotation
            {
                vec3 ctr = vec3(1,2,0);
                float S = 1.0f; float H = 1.0f;
                float theta = 2.0f*PI*RND;
                float ct = cosf(theta), st = sinf(theta);
                vec3 p0 = ctr + vec3(0.0f, 0.0f, -S);
                vec3 p1 = ctr + vec3(S, 0.0f, -S);
                vec3 p2 = ctr + vec3(S*0.5f, S*0.8660254f, -S);
                vec3 q0 = p0 + vec3(0.0f, 0.0f, H);
                vec3 q1 = p1 + vec3(0.0f, 0.0f, H);
                vec3 q2 = p2 + vec3(0.0f, 0.0f, H);
                {
                    vec3 r = p0 - ctr;
                    float rx = ct * r.x() + st * r.z();
                    float rz = -st * r.x() + ct * r.z();
                    p0 = vec3(rx + ctr.x(), r.y() + ctr.y(), rz + ctr.z());
                }
                {
                    vec3 r = p1 - ctr;
                    float rx = ct * r.x() + st * r.z();
                    float rz = -st * r.x() + ct * r.z();
                    p1 = vec3(rx + ctr.x(), r.y() + ctr.y(), rz + ctr.z());
                }
                {
                    vec3 r = p2 - ctr;
                    float rx = ct * r.x() + st * r.z();
                    float rz = -st * r.x() + ct * r.z();
                    p2 = vec3(rx + ctr.x(), r.y() + ctr.y(), rz + ctr.z());
                }
                {
                    vec3 r = q0 - ctr;
                    float rx = ct * r.x() + st * r.z();
                    float rz = -st * r.x() + ct * r.z();
                    q0 = vec3(rx + ctr.x(), r.y() + ctr.y(), rz + ctr.z());
                }
                {
                    vec3 r = q1 - ctr;
                    float rx = ct * r.x() + st * r.z();
                    float rz = -st * r.x() + ct * r.z();
                    q1 = vec3(rx + ctr.x(), r.y() + ctr.y(), rz + ctr.z());
                }
                {
                    vec3 r = q2 - ctr;
                    float rx = ct * r.x() + st * r.z();
                    float rz = -st * r.x() + ct * r.z();
                    q2 = vec3(rx + ctr.x(), r.y() + ctr.y(), rz + ctr.z());
                }
                d_list[i++] = new triangle(p0, p1, p2, new lambertian(vec3(0.4f, 0.2f, 0.1f)));
                d_list[i++] = new triangle(q0, q2, q1, new lambertian(vec3(0.4f, 0.2f, 0.1f)));
                d_list[i++] = new triangle(p0, p1, q1, new lambertian(vec3(0.4f, 0.2f, 0.1f)));
                d_list[i++] = new triangle(p0, q1, q0, new lambertian(vec3(0.4f, 0.2f, 0.1f)));
                d_list[i++] = new triangle(p1, p2, q2, new lambertian(vec3(0.4f, 0.2f, 0.1f)));
                d_list[i++] = new triangle(p1, q2, q1, new lambertian(vec3(0.4f, 0.2f, 0.1f)));
            }

            // Big prism 3 (metal) with random rotation
            {
                vec3 ctr = vec3(0,0,1);
                float S = 1.0f; float H = 1.0f;
                float theta = 2.0f*PI*RND;
                float ct = cosf(theta), st = sinf(theta);
                vec3 p0 = ctr + vec3(0.0f, 0.0f, -S);
                vec3 p1 = ctr + vec3(S, 0.0f, -S);
                vec3 p2 = ctr + vec3(S*0.5f, S*0.8660254f, -S);
                vec3 q0 = p0 + vec3(0.0f, 0.0f, H);
                vec3 q1 = p1 + vec3(0.0f, 0.0f, H);
                vec3 q2 = p2 + vec3(0.0f, 0.0f, H);
                {
                    vec3 r = p0 - ctr;
                    float rx = ct * r.x() + st * r.z();
                    float rz = -st * r.x() + ct * r.z();
                    p0 = vec3(rx + ctr.x(), r.y() + ctr.y(), rz + ctr.z());
                }
                {
                    vec3 r = p1 - ctr;
                    float rx = ct * r.x() + st * r.z();
                    float rz = -st * r.x() + ct * r.z();
                    p1 = vec3(rx + ctr.x(), r.y() + ctr.y(), rz + ctr.z());
                }
                {
                    vec3 r = p2 - ctr;
                    float rx = ct * r.x() + st * r.z();
                    float rz = -st * r.x() + ct * r.z();
                    p2 = vec3(rx + ctr.x(), r.y() + ctr.y(), rz + ctr.z());
                }
                {
                    vec3 r = q0 - ctr;
                    float rx = ct * r.x() + st * r.z();
                    float rz = -st * r.x() + ct * r.z();
                    q0 = vec3(rx + ctr.x(), r.y() + ctr.y(), rz + ctr.z());
                }
                {
                    vec3 r = q1 - ctr;
                    float rx = ct * r.x() + st * r.z();
                    float rz = -st * r.x() + ct * r.z();
                    q1 = vec3(rx + ctr.x(), r.y() + ctr.y(), rz + ctr.z());
                }
                {
                    vec3 r = q2 - ctr;
                    float rx = ct * r.x() + st * r.z();
                    float rz = -st * r.x() + ct * r.z();
                    q2 = vec3(rx + ctr.x(), r.y() + ctr.y(), rz + ctr.z());
                }
                d_list[i++] = new triangle(p0, p1, p2, new metal(vec3(0.7f, 0.6f, 0.5f), 0.0f));
                d_list[i++] = new triangle(q0, q2, q1, new metal(vec3(0.7f, 0.6f, 0.5f), 0.0f));
                d_list[i++] = new triangle(p0, p1, q1, new metal(vec3(0.7f, 0.6f, 0.5f), 0.0f));
                d_list[i++] = new triangle(p0, q1, q0, new metal(vec3(0.7f, 0.6f, 0.5f), 0.0f));
                d_list[i++] = new triangle(p1, p2, q2, new metal(vec3(0.7f, 0.6f, 0.5f), 0.0f));
                d_list[i++] = new triangle(p1, q2, q1, new metal(vec3(0.7f, 0.6f, 0.5f), 0.0f));
            }

            // Add two large spheres somewhere in the scene
            d_list[i++] = new sphere(vec3(2.0f, 3.0f, -1.0f), 1.0f, new lambertian(vec3(0.2f, 0.8f, 0.3f)));
            d_list[i++] = new sphere(vec3(2.0f, 1.0f, -1.0f), 1.0f, new metal(vec3(0.8f, 0.8f, 0.8f), 0.0f));
        }

        *rand_state = local_rand_state;
        *d_world  = new hitable_list(d_list, i);

        float aperture = 0.05;
        *d_camera   = new camera(lookfrom,
                                 lookat,
                                 vec3(0,2,0),
                                 20.0,
                                 float(nx)/float(ny),
                                 aperture,
                                 dist_to_focus);
    }
}

__global__ void free_world(hitable **d_list, hitable **d_world, camera **d_camera) {
    // read the actual list size from the world and delete only those entries
    hitable_list *world = (hitable_list *)(*d_world);
    int n = world->list_size;
    for(int i=0; i < n; i++) {
        if (d_list[i]) delete d_list[i];
    }
    delete *d_world;
    delete *d_camera;
}

int main(int argc, char** argv) {
    clock_t start, stop, start_render, mid, total;
    start = clock();
    // Increase stack and heap size for large mesh objects
    cudaDeviceSetLimit(cudaLimitStackSize, 32768);  // 32 KB stack
    cudaDeviceSetLimit(cudaLimitMallocHeapSize, 2048*1024*1024);  // 2 GB heap
    
    int nx = 480;
    int ny = 360;
    int ns = 1;
    int tx = 8;
    int ty = 8;
    
    // Check if an OBJ file was provided as argument
    std::string obj_file;
    bool use_mesh = false;
    int camera_view = 0;

    if (argc > 1) {
        obj_file = argv[1];
        if (is_directory(obj_file)) {
            std::string resolved_obj = find_obj_in_directory(obj_file);
            if (!resolved_obj.empty()) {
                std::cerr << "Directory provided; using OBJ: " << resolved_obj << std::endl;
                obj_file = resolved_obj;
                use_mesh = true;
            } else {
                std::cerr << "Error: No .obj file found in directory " << obj_file << std::endl;
                use_mesh = false;
            }
        } else {
            use_mesh = true;
            std::cerr << "Loading OBJ file: " << obj_file << std::endl;
        }

        if (argc == 3) {
            // Single extra argument remains a camera view, matching prior behavior.
            camera_view = parse_camera_view_arg(argv[2]);
        } else {
            int arg_index = 2;
            if (arg_index < argc && is_integer(argv[arg_index])) {
                nx = atoi(argv[arg_index]);
                arg_index++;
            }
            if (arg_index < argc && is_integer(argv[arg_index])) {
                ny = atoi(argv[arg_index]);
                arg_index++;
            }
            if (arg_index < argc && is_integer(argv[arg_index])) {
                ns = atoi(argv[arg_index]);
                arg_index++;
            }
            if (arg_index < argc) {
                std::string view_arg = argv[arg_index];
                camera_view = parse_camera_view_arg(view_arg);
            }
        }
    } else {
        std::cerr << "No OBJ file specified. Using default scene.\n";
        std::cerr << "Usage: raytracer.exe <path_to_obj_file> [width height samples] [camera_view]\n";
    }

    std::cerr << "Rendering a " << nx << "x" << ny << " image with " << ns << " samples per pixel ";
    std::cerr << "in " << tx << "x" << ty << " blocks.\n";

    // Load mesh from OBJ file if specified
    Mesh mesh;
    vec3 *d_mesh_vertices = nullptr;
    int *d_mesh_indices = nullptr;
    vec3 *d_mesh_texcoords = nullptr;
    int *d_mesh_texcoord_indices = nullptr;
    int *d_mesh_material_ids = nullptr;
    vec3 *d_material_colors = nullptr;
    material **d_materials = nullptr;
    unsigned char **d_material_texture_pixels = nullptr;
    unsigned char **h_material_texture_pixels = nullptr;
    int *d_material_texture_widths = nullptr;
    int *d_material_texture_heights = nullptr;
    int *d_material_texture_channels = nullptr;
    int num_indices = 0;
    int num_triangles = 0;
    int num_mesh_materials = 0;
    bool mesh_has_texcoords = false;
    vec3 lookfrom(100, 30, 20);
    vec3 lookat(0, 10, 0);
    float dist_to_focus = 1.0f;

    if (use_mesh) {
        mesh = OBJLoader::load(obj_file);
        num_indices = mesh.indices.size();
        num_triangles = num_indices / 3;
        num_mesh_materials = static_cast<int>(mesh.material_diffuse.size());

        if (num_indices == 0) {
            std::cerr << "Warning: Failed to load mesh or mesh is empty. Using default scene.\n";
            use_mesh = false;
        } else {
            if (num_mesh_materials == 0) {
                mesh.material_diffuse.push_back(vec3(0.6f, 0.6f, 0.6f));
                num_mesh_materials = 1;
            }
            if (static_cast<int>(mesh.material_ids.size()) != num_triangles) {
                mesh.material_ids.assign(num_triangles, 0);
            }

            if (num_triangles > 500000) {
                std::cerr << "Warning: Mesh has " << num_triangles << " triangles, which exceeds recommended limit of 500,000.\n";
                std::cerr << "Rendering may fail or be very slow.\n";
            }
            
            size_t vertex_size = mesh.vertices.size() * sizeof(vec3);
            size_t index_size = mesh.indices.size() * sizeof(int);
            size_t material_id_size = num_triangles * sizeof(int);
            size_t material_color_size = num_mesh_materials * sizeof(vec3);
            
            checkCudaErrors(cudaMalloc((void **)&d_mesh_vertices, vertex_size));
            checkCudaErrors(cudaMalloc((void **)&d_mesh_indices, index_size));
            checkCudaErrors(cudaMalloc((void **)&d_mesh_material_ids, material_id_size));
            checkCudaErrors(cudaMalloc((void **)&d_material_colors, material_color_size));
            checkCudaErrors(cudaMalloc((void **)&d_materials, num_mesh_materials * sizeof(material *)));
            
            size_t texcoord_size = mesh.texcoords.size() * sizeof(vec3);
            size_t texcoord_index_size = mesh.texcoord_indices.size() * sizeof(int);
            size_t texture_array_size = num_mesh_materials * sizeof(unsigned char *);
            size_t texture_meta_size = num_mesh_materials * sizeof(int);

            checkCudaErrors(cudaMemcpy(d_mesh_vertices, mesh.vertices.data(), vertex_size, cudaMemcpyHostToDevice));
            checkCudaErrors(cudaMemcpy(d_mesh_indices, mesh.indices.data(), index_size, cudaMemcpyHostToDevice));
            checkCudaErrors(cudaMemcpy(d_mesh_material_ids, mesh.material_ids.data(), material_id_size, cudaMemcpyHostToDevice));
            checkCudaErrors(cudaMemcpy(d_material_colors, mesh.material_diffuse.data(), material_color_size, cudaMemcpyHostToDevice));
            if (texcoord_size > 0 && texcoord_index_size > 0) {
                checkCudaErrors(cudaMalloc((void **)&d_mesh_texcoords, texcoord_size));
                checkCudaErrors(cudaMalloc((void **)&d_mesh_texcoord_indices, texcoord_index_size));
                checkCudaErrors(cudaMemcpy(d_mesh_texcoords, mesh.texcoords.data(), texcoord_size, cudaMemcpyHostToDevice));
                checkCudaErrors(cudaMemcpy(d_mesh_texcoord_indices, mesh.texcoord_indices.data(), texcoord_index_size, cudaMemcpyHostToDevice));
                mesh_has_texcoords = true;
            }

            unsigned char **h_material_texture_pixels = new unsigned char *[num_mesh_materials];
            int *h_material_texture_widths = new int[num_mesh_materials];
            int *h_material_texture_heights = new int[num_mesh_materials];
            int *h_material_texture_channels = new int[num_mesh_materials];
            for (int m = 0; m < num_mesh_materials; m++) {
                h_material_texture_pixels[m] = nullptr;
                h_material_texture_widths[m] = 0;
                h_material_texture_heights[m] = 0;
                h_material_texture_channels[m] = 0;
            }
            
            for (int m = 0; m < num_mesh_materials; m++) {
                if (m < static_cast<int>(mesh.material_texture_filenames.size()) && !mesh.material_texture_filenames[m].empty()) {
                    std::string texture_path = mesh.material_texture_filenames[m];
                    int width, height, channels;
                    unsigned char *image_data = stbi_load(texture_path.c_str(), &width, &height, &channels, 0);
                    if (image_data != nullptr && width > 0 && height > 0 && channels > 0) {
                        size_t pixel_count = static_cast<size_t>(width) * height * channels;
                        checkCudaErrors(cudaMalloc((void **)&h_material_texture_pixels[m], pixel_count * sizeof(unsigned char)));
                        checkCudaErrors(cudaMemcpy(h_material_texture_pixels[m], image_data, pixel_count * sizeof(unsigned char), cudaMemcpyHostToDevice));
                        h_material_texture_widths[m] = width;
                        h_material_texture_heights[m] = height;
                        h_material_texture_channels[m] = channels;
                        std::cerr << "Loaded texture for material " << m << ": " << texture_path << " (" << width << "x" << height << "x" << channels << ")" << std::endl;
                    } else {
                        std::cerr << "Warning: Failed to load texture " << texture_path << std::endl;
                    }
                    if (image_data) stbi_image_free(image_data);
                }
            }

            checkCudaErrors(cudaMalloc((void **)&d_material_texture_pixels, texture_array_size));
            checkCudaErrors(cudaMalloc((void **)&d_material_texture_widths, texture_meta_size));
            checkCudaErrors(cudaMalloc((void **)&d_material_texture_heights, texture_meta_size));
            checkCudaErrors(cudaMalloc((void **)&d_material_texture_channels, texture_meta_size));
            checkCudaErrors(cudaMemcpy(d_material_texture_pixels, h_material_texture_pixels, texture_array_size, cudaMemcpyHostToDevice));
            checkCudaErrors(cudaMemcpy(d_material_texture_widths, h_material_texture_widths, texture_meta_size, cudaMemcpyHostToDevice));
            checkCudaErrors(cudaMemcpy(d_material_texture_heights, h_material_texture_heights, texture_meta_size, cudaMemcpyHostToDevice));
            checkCudaErrors(cudaMemcpy(d_material_texture_channels, h_material_texture_channels, texture_meta_size, cudaMemcpyHostToDevice));

            delete[] h_material_texture_widths;
            delete[] h_material_texture_heights;
            delete[] h_material_texture_channels;

            compute_camera_for_mesh(mesh, camera_view, lookfrom, lookat, dist_to_focus);
            std::cerr << "Mesh data uploaded to GPU\n";
            std::cerr << "Camera view: " << camera_view_name(camera_view) << "\n";
        }
    }

    if (!use_mesh) {
        dist_to_focus = (lookfrom - lookat).length();
    }

    int num_pixels = nx*ny;
    size_t fb_size = num_pixels*sizeof(vec3);

    // allocate FB
    vec3 *fb;
    checkCudaErrors(cudaMallocManaged((void **)&fb, fb_size));

    // allocate random state
    curandState *d_rand_state;
    checkCudaErrors(cudaMalloc((void **)&d_rand_state, num_pixels*sizeof(curandState)));
    curandState *d_rand_state2;
    checkCudaErrors(cudaMalloc((void **)&d_rand_state2, 1*sizeof(curandState)));

    // we need that 2nd random state to be initialized for the world creation
    rand_init<<<1,1>>>(d_rand_state2);
    checkCudaErrors(cudaGetLastError());
    checkCudaErrors(cudaDeviceSynchronize());

    // make our world of hitables & the camera
    hitable **d_list;
    int num_hitables;
    
    if (use_mesh) {
        // For mesh path we use one hitable object instead of one per triangle
        num_hitables = 2;
        std::cerr << "Preparing to load mesh as a single hitable object\n";
    } else {
        // Original hardcoded scene
        num_hitables = 22*22*6 + 18 + 2 + 2;
    }
    
    checkCudaErrors(cudaMalloc((void **)&d_list, num_hitables*sizeof(hitable *)));
    hitable **d_world;
    checkCudaErrors(cudaMalloc((void **)&d_world, sizeof(hitable *)));
    camera **d_camera;
    checkCudaErrors(cudaMalloc((void **)&d_camera, sizeof(camera *)));
    
    std::cerr << "Launching create_world kernel...\n";
    create_world<<<1,1>>>(d_list, d_world, d_camera, nx, ny, d_rand_state2,
                          d_mesh_vertices, d_mesh_indices, num_indices,
                          d_mesh_texcoords, d_mesh_texcoord_indices, mesh_has_texcoords,
                          d_mesh_material_ids, d_material_colors, d_materials, num_mesh_materials,
                          d_material_texture_pixels, d_material_texture_widths, d_material_texture_heights, d_material_texture_channels,
                          lookfrom, lookat, dist_to_focus, use_mesh);
    
    cudaError_t err = cudaGetLastError();
    if (err != cudaSuccess) {
        std::cerr << "Kernel launch error: " << cudaGetErrorString(err) << " (" << err << ")\n";
        return -1;
    }
    
    err = cudaDeviceSynchronize();
    if (err != cudaSuccess) {
        std::cerr << "Kernel execution error: " << cudaGetErrorString(err) << " (" << err << ")\n";
        return -1;
    }
    
    mid = clock();
    double setup_seconds = ((double)(mid - start)) / CLOCKS_PER_SEC;

    std::cerr << "\nWorld created successfully in " << setup_seconds << " seconds\n\n";
    std::cerr << "Starting Ray Trace\n";

    start_render = clock();
    // Render our buffer
    dim3 blocks(nx/tx+1,ny/ty+1);
    dim3 threads(tx,ty);
    render_init<<<blocks, threads>>>(nx, ny, d_rand_state);
    checkCudaErrors(cudaGetLastError());
    checkCudaErrors(cudaDeviceSynchronize());
    render<<<blocks, threads>>>(fb, nx, ny,  ns, d_camera, d_world, d_rand_state);
    checkCudaErrors(cudaGetLastError());
    checkCudaErrors(cudaDeviceSynchronize());
    stop = clock();
    double timer_seconds = ((double)(stop - start_render)) / CLOCKS_PER_SEC;
    std::cerr << "\nRay Trace took " << timer_seconds << " seconds.\n\n";

    // Output FB as Image to file
    std::ofstream image_file("image.ppm");
    if (!image_file.is_open()) {
        std::cerr << "Error: Could not create image.ppm file\n";
        return -1;
    }
    
    image_file << "P3\n" << nx << " " << ny << "\n255\n";
    for (int j = ny-1; j >= 0; j--) {
        for (int i = 0; i < nx; i++) {
            size_t pixel_index = j*nx + i;
            int ir = int(255.99*fb[pixel_index].r());
            int ig = int(255.99*fb[pixel_index].g());
            int ib = int(255.99*fb[pixel_index].b());
            image_file << ir << " " << ig << " " << ib << "\n";
        }
    }
    image_file.close();
    
    std::cerr << "Image saved to image.ppm\n";
    std::cerr << "Starting Memory Cleanup. Don't Quit\n";
    // clean up
    checkCudaErrors(cudaDeviceSynchronize());
    free_world<<<1,1>>>(d_list,d_world,d_camera);
    checkCudaErrors(cudaGetLastError());
    checkCudaErrors(cudaFree(d_camera));
    checkCudaErrors(cudaFree(d_world));
    checkCudaErrors(cudaFree(d_list));
    checkCudaErrors(cudaFree(d_rand_state));
    checkCudaErrors(cudaFree(d_rand_state2));
    checkCudaErrors(cudaFree(fb));
    
    // Free mesh GPU memory if it was allocated
    if (d_mesh_vertices != nullptr) {
        checkCudaErrors(cudaFree(d_mesh_vertices));
    }
    if (d_mesh_indices != nullptr) {
        checkCudaErrors(cudaFree(d_mesh_indices));
    }
    if (d_mesh_material_ids != nullptr) {
        checkCudaErrors(cudaFree(d_mesh_material_ids));
    }
    if (d_material_colors != nullptr) {
        checkCudaErrors(cudaFree(d_material_colors));
    }
    if (d_materials != nullptr) {
        checkCudaErrors(cudaFree(d_materials));
    }
    if (d_mesh_texcoords != nullptr) {
        checkCudaErrors(cudaFree(d_mesh_texcoords));
    }
    if (d_mesh_texcoord_indices != nullptr) {
        checkCudaErrors(cudaFree(d_mesh_texcoord_indices));
    }
    if (d_material_texture_pixels != nullptr) {
        checkCudaErrors(cudaFree(d_material_texture_pixels));
    }
    if (d_material_texture_widths != nullptr) {
        checkCudaErrors(cudaFree(d_material_texture_widths));
    }
    if (d_material_texture_heights != nullptr) {
        checkCudaErrors(cudaFree(d_material_texture_heights));
    }
    if (d_material_texture_channels != nullptr) {
        checkCudaErrors(cudaFree(d_material_texture_channels));
    }
    if (h_material_texture_pixels != nullptr) {
        for (int i = 0; i < num_mesh_materials; i++) {
            if (h_material_texture_pixels[i] != nullptr) {
                checkCudaErrors(cudaFree(h_material_texture_pixels[i]));
            }
        }
        delete[] h_material_texture_pixels;
    }

    cudaDeviceReset();
    std::cerr << "Finished Cleanup\n";
    total = clock();
    double total_seconds = ((double)(total - start)) / CLOCKS_PER_SEC;
    std::cerr << "\nTotal execution time: " << total_seconds << " seconds\n";

}