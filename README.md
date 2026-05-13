# CUDA OBJ Ray Tracer

A simple GPU-accelerated ray tracing renderer for OBJ mesh models, built with CUDA and C++.

This project is centered in the `RayTracer` folder and loads `.obj` geometry with optional `.mtl` materials and textures. It compiles `main.cu` with `nvcc`, renders a scene on an NVIDIA GPU, and outputs the final image as `image.ppm`.

## Project Structure

- `RayTracer/`
  - `render_obj.bat` - helper script to compile and run the tracer.
  - `models/` - mesh assets and materials.
  - `src/` - ray tracer source files, including `main.cu` and supporting headers.

## Requirements

- Windows 10 or 11
- NVIDIA GPU with CUDA support
- CUDA Toolkit installed (includes `nvcc`)
- Microsoft Visual Studio Build Tools or full Visual Studio with C++ workload
- `nvcc` and the Visual Studio x64 build environment available to the script

> Note: `render_obj.bat` currently calls Visual Studio 2022 Build Tools at:
> `C:\Program Files (x86)\Microsoft Visual Studio\2022\BuildTools\VC\Auxiliary\Build\vcvarsall.bat`
> Update this path if your Visual Studio installation differs.

## Setup

1. Open a PowerShell terminal.
2. Change directory to the ray tracer folder:

```powershell
cd "C:\Users\lukej\OneDrive\Documentos\Senior_Capstone\Capstone\RayTracer"
```

3. Confirm that `nvcc` is available and the CUDA Toolkit is installed.
4. Make sure the Visual Studio x64 environment path in `render_obj.bat` matches your installed toolchain.

## How to Run

### Recommended: use the helper script

```powershell
.
render_obj.bat "models\car\" 1920 1080 50 0 0 100
```

This will:
- compile `RayTracer\src\main.cu` into `main.exe`
- run the ray tracer on the first `.obj` inside `models\car\`
- create `image.ppm` in `RayTracer\src`

### Direct invocation

If you prefer to compile manually:

```powershell
cd "RayTracer\src"
nvcc main.cu -o main.exe
main.exe "..\models\car\Car.obj" 1280 720 25 0 0 80
```

## Command-Line Options

The executable accepts the OBJ path followed by optional rendering and camera parameters.

```text
main.exe <obj_path_or_directory> [width height samples] [azimuth elevation] [radius]

```

### Parameters

- `<obj_path_or_directory>` - path to a `.obj` file or a directory containing a `.obj`
- `width` - output image width in pixels (default: `480`)
- `height` - output image height in pixels (default: `360`)
- `samples` - samples per pixel for anti-aliasing (default: `1`)
- `azimuth` / `elevation` - camera rotation angles in degrees (0–360)
- `radius` - optional camera distance override from the mesh


## Examples

Render using a directory containing an OBJ file:

```powershell
.
render_obj.bat "models\car\"
```

Render with custom resolution and samples:

```powershell
.
render_obj.bat "models\car\" 1280 720 32
```

Render with explicit spherical camera angles:

```powershell
.
render_obj.bat "models\car\" 1920 1080 50 180 30 130
```

## Output

- Output file: `RayTracer\src\image.ppm`
- Format: plain PPM (`P3`)

## Notes

- Rendering high resolutions or many samples can be slow.
- If the script fails to locate `vcvarsall.bat`, update the path in `render_obj.bat`.
- If `render_obj.bat` cannot find a `.obj`, ensure the provided input path exists and contains at least one `.obj` file.

## Troubleshooting

- `nvcc` not found: verify CUDA Toolkit installation and add it to your PATH.
- `vcvarsall.bat` path invalid: update the hard-coded Visual Studio path in `render_obj.bat`.
- No output image: confirm the program completed successfully and that `image.ppm` was saved in `RayTracer\src`.

## Math-402 Capstone: The Rendering Equation and Monte Carlo Integration

For those interested, in `Math_capstone\` you can find my math capstone research of the rendering equation and Monte Carlo integration
