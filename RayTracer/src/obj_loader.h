#ifndef OBJ_LOADER_H
#define OBJ_LOADER_H

#include <vector>
#include <fstream>
#include <sstream>
#include <string>
#include <iostream>
#include <unordered_map>
#include "vec3.h"

struct Mesh {
    std::vector<vec3> vertices;
    std::vector<vec3> texcoords;
    std::vector<int> indices;            // Triangle indices: each 3 consecutive indices form a triangle
    std::vector<int> texcoord_indices;   // Texture coordinate indices: each 3 consecutive indices form a triangle
    std::vector<int> material_ids;       // Material index for each triangle
    std::vector<vec3> material_diffuse;  // Diffuse color per material
    std::vector<std::string> material_texture_filenames;
};

class OBJLoader {
public:
    static Mesh load(const std::string& filename) {
        Mesh mesh;
        std::unordered_map<std::string, int> material_map;
        mesh.material_diffuse.push_back(vec3(0.6f, 0.6f, 0.6f));
        mesh.material_texture_filenames.push_back(std::string());
        material_map["default"] = 0;
        int current_material = 0;

        std::ifstream file(filename);
        if (!file.is_open()) {
            std::cerr << "Error: Could not open file " << filename << std::endl;
            return mesh;
        }

        std::string base_dir = directoryOf(filename);
        std::string line;
        while (std::getline(file, line)) {
            if (line.empty() || line[0] == '#') continue;

            std::istringstream iss(line);
            std::string token;
            iss >> token;

            if (token == "mtllib") {
                std::string mtl_file;
                iss >> mtl_file;
                if (!mtl_file.empty()) {
                    load_mtl(base_dir + mtl_file, material_map, mesh);
                }
            }
            else if (token == "usemtl") {
                std::string material_name;
                iss >> material_name;
                if (material_name.empty()) continue;

                auto it = material_map.find(material_name);
                if (it == material_map.end()) {
                    current_material = static_cast<int>(mesh.material_diffuse.size());
                    material_map[material_name] = current_material;
                    mesh.material_diffuse.push_back(vec3(0.6f, 0.6f, 0.6f));
                    mesh.material_texture_filenames.push_back(std::string());
                } else {
                    current_material = it->second;
                }
            }
            else if (token == "v") {
                float x, y, z;
                iss >> x >> y >> z;
                mesh.vertices.push_back(vec3(x, y, z));
            }
            else if (token == "vt") {
                float u, v;
                iss >> u >> v;
                mesh.texcoords.push_back(vec3(u, v, 0.0f));
            }
            else if (token == "f") {
                std::string vertex_str;
                std::vector<int> face_indices;
                std::vector<int> face_texcoords;
                while (iss >> vertex_str) {
                    int vertex_index = -1;
                    int texcoord_index = -1;
                    size_t first_slash = vertex_str.find('/');
                    if (first_slash == std::string::npos) {
                        vertex_index = std::stoi(vertex_str);
                    } else {
                        vertex_index = std::stoi(vertex_str.substr(0, first_slash));
                        size_t second_slash = vertex_str.find('/', first_slash + 1);
                        if (second_slash == std::string::npos) {
                            texcoord_index = std::stoi(vertex_str.substr(first_slash + 1));
                        } else if (second_slash > first_slash + 1) {
                            texcoord_index = std::stoi(vertex_str.substr(first_slash + 1, second_slash - first_slash - 1));
                        }
                    }
                    face_indices.push_back(vertex_index - 1);
                    face_texcoords.push_back(texcoord_index - 1);
                }

                if (face_indices.size() >= 3) {
                    for (size_t i = 1; i < face_indices.size() - 1; i++) {
                        mesh.indices.push_back(face_indices[0]);
                        mesh.indices.push_back(face_indices[i]);
                        mesh.indices.push_back(face_indices[i + 1]);
                        mesh.texcoord_indices.push_back(face_texcoords[0]);
                        mesh.texcoord_indices.push_back(face_texcoords[i]);
                        mesh.texcoord_indices.push_back(face_texcoords[i + 1]);
                        mesh.material_ids.push_back(current_material);
                    }
                }
            }
        }

        file.close();

        std::cerr << "Loaded OBJ: " << filename << std::endl;
        std::cerr << "  Vertices: " << mesh.vertices.size() << std::endl;
        std::cerr << "  Triangles: " << (mesh.indices.size() / 3) << std::endl;
        std::cerr << "  Materials: " << mesh.material_diffuse.size() << std::endl;

        return mesh;
    }

private:
    static std::string directoryOf(const std::string& path) {
        size_t pos = path.find_last_of("/\\");
        if (pos == std::string::npos) return std::string();
        return path.substr(0, pos + 1);
    }

    static void load_mtl(const std::string& filename,
                         std::unordered_map<std::string, int>& material_map,
                         Mesh& mesh) {
        std::ifstream file(filename);
        if (!file.is_open()) {
            std::cerr << "Warning: Could not open MTL file " << filename << std::endl;
            return;
        }

        std::string line;
        int current_material = -1;
        std::string current_name;
        while (std::getline(file, line)) {
            if (line.empty() || line[0] == '#') continue;

            std::istringstream iss(line);
            std::string token;
            iss >> token;

            if (token == "newmtl") {
                iss >> current_name;
                if (current_name.empty()) continue;
                auto it = material_map.find(current_name);
                if (it == material_map.end()) {
                    current_material = static_cast<int>(mesh.material_diffuse.size());
                    material_map[current_name] = current_material;
                    mesh.material_diffuse.push_back(vec3(0.6f, 0.6f, 0.6f));
                    mesh.material_texture_filenames.push_back(std::string());
                } else {
                    current_material = it->second;
                }
            }
            else if (token == "Kd") {
                float r, g, b;
                iss >> r >> g >> b;
                if (current_material < 0) {
                    current_material = 0;
                }
                if (current_material >= static_cast<int>(mesh.material_diffuse.size())) {
                    mesh.material_diffuse.resize(current_material + 1, vec3(0.6f, 0.6f, 0.6f));
                    mesh.material_texture_filenames.resize(current_material + 1);
                }
                mesh.material_diffuse[current_material] = vec3(r, g, b);
            }
            else if (token == "map_Kd") {
                std::string texture_file;
                iss >> texture_file;
                if (texture_file.empty()) continue;
                if (current_material < 0) {
                    current_material = 0;
                }
                if (current_material >= static_cast<int>(mesh.material_texture_filenames.size())) {
                    mesh.material_texture_filenames.resize(current_material + 1);
                }
                mesh.material_texture_filenames[current_material] = directoryOf(filename) + texture_file;
            }
        }

        file.close();
    }
};

#endif // OBJ_LOADER_H
