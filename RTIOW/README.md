# Ray Tracing in One Weekend (RTIOW)

This project generates a simple gradient image using C++ and outputs it in PPM format.

## Prerequisites

- CMake (version 3.16 or higher)
- C++ compiler supporting C++17 (Visual Studio 2019+ on Windows)

## Building the Project

### Option 1: Using CMake directly

1. Navigate to the project directory:
   ```powershell
   cd "c:\Users\lukej\Documents\Capstone\RTIOW"
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

## Customization

You can modify the image dimensions by changing the `image_width` and `image_height` variables in `main.cc`. Remember to rebuild after making changes.

## CMake Targets

- `rtiow`: Main executable target
- `run_rtiow`: Custom target that builds and runs the program, generating `image.ppm`

To use the custom target:
```powershell
cmake --build . --target run_rtiow
```