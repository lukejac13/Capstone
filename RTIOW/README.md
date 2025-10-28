# Ray Tracing in One Weekend (RTIOW)

This project implements a physically-based ray tracer that generates photorealistic images using Monte Carlo sampling and the rendering equation. The program uses multithreaded CPU rendering for improved performance.

## Mathematical Foundation

### The Rendering Equation

The core of ray tracing is based on the rendering equation, which describes how light interacts with surfaces:

$$L_o(p, \omega_o) = L_e(p, \omega_o) + \int_{\Omega} f_r(p, \omega_i, \omega_o) L_i(p, \omega_i) \cos\theta_i d\omega_i$$

Where:
- $L_o(p, \omega_o)$ is the outgoing radiance at point $p$ in direction $\omega_o$
- $L_e(p, \omega_o)$ is the emitted radiance (for light sources)
- $f_r(p, \omega_i, \omega_o)$ is the bidirectional reflectance distribution function (BRDF)
- $L_i(p, \omega_i)$ is the incoming radiance from direction $\omega_i$
- $\cos\theta_i$ is the cosine of the angle between $\omega_i$ and the surface normal
- $\Omega$ represents the hemisphere of incoming directions

### Monte Carlo Integration

Since the rendering equation involves an integral over all incoming directions, we use Monte Carlo integration to approximate it:

$$\int_{\Omega} f(x) dx \approx \frac{1}{N} \sum_{i=1}^{N} \frac{f(x_i)}{p(x_i)}$$

Where $N$ is the number of samples and $p(x_i)$ is the probability density function for sample $x_i$.

### Ray-Sphere Intersection

For sphere intersection testing, we solve the quadratic equation:

$$t^2(\mathbf{d} \cdot \mathbf{d}) + 2t(\mathbf{d} \cdot (\mathbf{o} - \mathbf{c})) + (\mathbf{o} - \mathbf{c}) \cdot (\mathbf{o} - \mathbf{c}) - r^2 = 0$$

Where:
- $\mathbf{o}$ is the ray origin
- $\mathbf{d}$ is the ray direction
- $\mathbf{c}$ is the sphere center
- $r$ is the sphere radius

## Prerequisites

- CMake (version 3.16 or higher)
- C++ compiler supporting C++17 (Visual Studio 2019+ on Windows)

## Building the Project

### Option 1: Using CMake directly

1. Navigate to the project directory:
   ```powershell
   cd "\Capstone\RTIOW"
   ```

2. Create and navigate to build directory:
   ```powershell
   mkdir build
   cd build
   ```

3. Configure the project:
   ```powershell
   cmake ..
   ```

4. Build the project:
   ```powershell
   cmake --build . --config Release
   ```

### Option 2: Using the provided scripts

From the `build` directory, run:
```powershell
# PowerShell script
.\build_and_run.ps1

# Or batch script
.\build_and_run.bat
```

## Running the Program

After building, the executable will be located at `build/bin/Release/rtiow.exe`.

To generate an image:
```powershell
.\bin\Release\rtiow.exe > image.ppm
```

This will create a 256x256 pixel PPM image file.

## Viewing the Generated Image

The program outputs a PPM (Portable Pixmap) file. To view it:

1. **Convert to PNG** (easiest method):
   - Use the Python conversion script from the parent directory
   - Or use online PPM to PNG converters

2. **Use specialized viewers**:
   - GIMP (free image editor)
   - IrfanView (Windows image viewer)
   - VS Code with image preview extensions

3. **Direct viewing**:
   - Some image viewers support PPM format directly

## Project Structure

```
RTIOW/
├── main.cc              # Main C++ source file
├── CMakeLists.txt       # CMake configuration file
├── build/               # Build directory
│   ├── bin/Release/     # Compiled executable location
│   ├── build_and_run.ps1  # PowerShell build script
│   ├── build_and_run.bat  # Batch build script
│   └── ...              # CMake generated files
└── README.md            # This file
```

## Multithreading Implementation

This ray tracer uses multithreaded CPU rendering for improved performance:

- **Work Distribution**: Rows are distributed dynamically among threads using atomic counters
- **Thread Safety**: Uses thread-local random number generators for proper parallel execution  
- **Performance**: Automatically detects and utilizes all available CPU cores
- **Progress Reporting**: Thread-safe progress updates during rendering

### Performance Comparison

The multithreaded implementation provides significant speedup over single-threaded rendering:
- **Single-threaded**: Linear processing, one pixel at a time
- **Multithreaded**: Parallel processing across all CPU cores

To switch between modes, modify the render call in `main.cc`:
```cpp
// Multithreaded (default)
cam.render(world);

// Single-threaded (for comparison)
cam.render_single_threaded(world);
```

## Customization

You can modify the rendering parameters in `main.cc`:
- `image_width`: Output image width (affects render time)
- `samples_per_pixel`: Number of samples per pixel (affects quality and render time)
- `max_depth`: Maximum ray bounce depth (affects quality)

Remember to rebuild after making changes.

## CMake Targets

- `rtiow`: Main executable target
- `run_rtiow`: Custom target that builds and runs the program, generating `image.ppm`

To use the custom target:
```powershell
cmake --build . --target run_rtiow
```