#include <iostream>
#include <fstream>
#include <time.h>
#include <float.h>
#include <curand_kernel.h>
#include <string>
#include "vec3.h"
#include "ray.h"
#include "sphere.h"
#include "triangle.h"
#include "hitable_list.h"
#include "camera.h"
#include "material.h"
#include "obj_loader.h"

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
                             vec3 *mesh_vertices, int *mesh_indices, int num_indices, bool use_mesh) {
    if (threadIdx.x == 0 && blockIdx.x == 0) {
        // Create a ground (two large triangles) and a grid of small triangular prisms
        curandState local_rand_state = *rand_state;
        int i = 0;

        if (use_mesh && mesh_vertices != nullptr && mesh_indices != nullptr && num_indices > 0) {
            // Load triangles from mesh
            int num_triangles = num_indices / 3;
            printf("Creating %d triangles from mesh...\n", num_triangles);
            
            for (int tri = 0; tri < num_triangles; tri++) {
                if (tri % 20000 == 0) {
                    printf("  Allocated %d/%d triangles...\n", tri, num_triangles);
                }
                int idx0 = mesh_indices[tri * 3];
                int idx1 = mesh_indices[tri * 3 + 1];
                int idx2 = mesh_indices[tri * 3 + 2];
                
                vec3 v0 = mesh_vertices[idx0];
                vec3 v1 = mesh_vertices[idx1];
                vec3 v2 = mesh_vertices[idx2];
                
                // Create triangle with a default material (you can vary this)
                float choose_mat = .5;
                material *mat;
                if (choose_mat < 0.7f) {
                    mat = new lambertian(vec3(0.3f, 0.3f, 0.3f));
                } else if (choose_mat > 0.95f) {
                    mat = new metal(vec3(0.5f*(1.0f+RND), 0.5f*(1.0f+RND), 0.5f*(1.0f+RND)), 0.5f*RND);
                }else{
                    mat = new lambertian(vec3(0.5f + 0.5f*RND, 0.5f + 0.5f*RND, 0.5f + 0.5f*RND));
                }
                
                d_list[i++] = new triangle(v0, v1, v2, mat);
            }
            printf("Successfully created all %d triangles\n", num_triangles);
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

        vec3 lookfrom(20, 20, 100);
        vec3 lookat(0, 10, 0);
        float dist_to_focus = (lookfrom-lookat).length();
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
    
    int nx = 1920;
    int ny = 1080;
    int ns = 30;
    int tx = 8;
    int ty = 8;
    
    // Check if an OBJ file was provided as argument
    std::string obj_file;
    bool use_mesh = false;
    
    if (argc > 1) {
        obj_file = argv[1];
        use_mesh = true;
        std::cerr << "Loading OBJ file: " << obj_file << std::endl;
    } else {
        std::cerr << "No OBJ file specified. Using default scene.\n";
        std::cerr << "Usage: raytracer.exe <path_to_obj_file>\n";
    }

    std::cerr << "Rendering a " << nx << "x" << ny << " image with " << ns << " samples per pixel ";
    std::cerr << "in " << tx << "x" << ty << " blocks.\n";

    // Load mesh from OBJ file if specified
    Mesh mesh;
    vec3 *d_mesh_vertices = nullptr;
    int *d_mesh_indices = nullptr;
    int num_indices = 0;
    
    if (use_mesh) {
        mesh = OBJLoader::load(obj_file);
        num_indices = mesh.indices.size();
        
        if (num_indices == 0) {
            std::cerr << "Warning: Failed to load mesh or mesh is empty. Using default scene.\n";
            use_mesh = false;
        } else {
            // Check if mesh is too large
            int num_triangles = num_indices / 3;
            if (num_triangles > 500000) {
                std::cerr << "Warning: Mesh has " << num_triangles << " triangles, which exceeds recommended limit of 500,000.\n";
                std::cerr << "Rendering may fail or be very slow.\n";
            }
            
            // Allocate GPU memory for mesh data
            size_t vertex_size = mesh.vertices.size() * sizeof(vec3);
            size_t index_size = mesh.indices.size() * sizeof(int);
            
            checkCudaErrors(cudaMalloc((void **)&d_mesh_vertices, vertex_size));
            checkCudaErrors(cudaMalloc((void **)&d_mesh_indices, index_size));
            
            // Copy mesh data to GPU
            checkCudaErrors(cudaMemcpy(d_mesh_vertices, mesh.vertices.data(), vertex_size, cudaMemcpyHostToDevice));
            checkCudaErrors(cudaMemcpy(d_mesh_indices, mesh.indices.data(), index_size, cudaMemcpyHostToDevice));
            
            std::cerr << "Mesh data uploaded to GPU\n";
        }
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
        // Allocate enough space for mesh triangles
        num_hitables = (num_indices / 3) + 100;
        std::cerr << "Preparing to load " << num_hitables << " hitables for mesh\n";
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
    create_world<<<1,1>>>(d_list, d_world, d_camera, nx, ny, d_rand_state2, d_mesh_vertices, d_mesh_indices, num_indices, use_mesh);
    
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

    cudaDeviceReset();
    std::cerr << "Finished Cleanup\n";
    total = clock();
    double total_seconds = ((double)(total - start)) / CLOCKS_PER_SEC;
    std::cerr << "\nTotal execution time: " << total_seconds << " seconds\n";

}