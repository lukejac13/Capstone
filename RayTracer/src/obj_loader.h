#ifndef OBJ_LOADER_H
#define OBJ_LOADER_H

#include <vector>
#include <fstream>
#include <sstream>
#include <string>
#include <iostream>
#include "vec3.h"

struct Mesh {
    std::vector<vec3> vertices;
    std::vector<int> indices;  // Triangle indices: each 3 consecutive indices form a triangle
};

class OBJLoader {
public:
    static Mesh load(const std::string& filename) {
        Mesh mesh;
        std::ifstream file(filename);
        
        if (!file.is_open()) {
            std::cerr << "Error: Could not open file " << filename << std::endl;
            return mesh;
        }
        
        std::string line;
        while (std::getline(file, line)) {
            // Skip empty lines and comments
            if (line.empty() || line[0] == '#') continue;
            
            std::istringstream iss(line);
            std::string token;
            iss >> token;
            
            if (token == "v") {
                // Vertex position
                float x, y, z;
                iss >> x >> y >> z;
                mesh.vertices.push_back(vec3(x, y, z));
            }
            else if (token == "f") {
                // Face (triangle)
                std::string vertex_str;
                std::vector<int> face_indices;
                
                while (iss >> vertex_str) {
                    // Handle formats like: "1", "1/2", "1/2/3", "1//3"
                    int vertex_index = -1;
                    
                    // Extract only the vertex position index (first number)
                    size_t slash_pos = vertex_str.find('/');
                    if (slash_pos != std::string::npos) {
                        vertex_index = std::stoi(vertex_str.substr(0, slash_pos));
                    } else {
                        vertex_index = std::stoi(vertex_str);
                    }
                    
                    // OBJ indices are 1-based, convert to 0-based
                    face_indices.push_back(vertex_index - 1);
                }
                
                // Triangulate if necessary (handle n-gons by fanning)
                if (face_indices.size() >= 3) {
                    for (size_t i = 1; i < face_indices.size() - 1; i++) {
                        mesh.indices.push_back(face_indices[0]);
                        mesh.indices.push_back(face_indices[i]);
                        mesh.indices.push_back(face_indices[i + 1]);
                    }
                }
            }
        }
        
        file.close();
        
        std::cerr << "Loaded OBJ: " << filename << std::endl;
        std::cerr << "  Vertices: " << mesh.vertices.size() << std::endl;
        std::cerr << "  Triangles: " << (mesh.indices.size() / 3) << std::endl;
        
        return mesh;
    }
};

#endif // OBJ_LOADER_H
