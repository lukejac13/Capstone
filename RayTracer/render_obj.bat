@echo off
REM Script to easily render OBJ files with the ray tracer
REM Usage: render_obj.bat path\to\model.obj

if "%1"=="" (
    echo Usage: render_obj.bat ^<path_to_obj_file_or_directory^> [width height samples] [camera_view]
    echo.
    echo Example:
    echo   render_obj.bat models\cube.obj
    echo   render_obj.bat models\cube_dir 1920 1080 50 front-left
    echo   render_obj.bat C:\path\to\my_model.obj 1280 720 16 back-right
    exit /b 1
)

set "INPUT=%~1"
set "OBJ_PATH="

REM If the input is a directory, find the first .obj file inside it.
if exist "%INPUT%\" (
    for %%F in ("%INPUT%\*.obj") do if not defined OBJ_PATH set "OBJ_PATH=%%~fF"
) else if exist "%INPUT%" (
    for %%F in ("%INPUT%") do set "OBJ_PATH=%%~fF"
) else (
    REM Try relative to RayTracer directory
    if exist "models\%INPUT%" (
        for %%F in ("models\%INPUT%") do set "OBJ_PATH=%%~fF"
    )
)

if "%OBJ_PATH%"=="" (
    echo Error: No OBJ file found for input: %1
    exit /b 1
)

echo Attempting to load: %OBJ_PATH%

echo Setting up CUDA development environment...
call "C:\Program Files (x86)\Microsoft Visual Studio\2022\BuildTools\VC\Auxiliary\Build\vcvarsall.bat" x64

echo Navigating to source directory...
cd /d "%~dp0src"

echo Compiling CUDA program...
nvcc main.cu -o main.exe

if %ERRORLEVEL% EQU 0 (
    echo Compilation successful!
    echo.
    echo Rendering: %OBJ_PATH%
    echo.
    main.exe "%OBJ_PATH%" %~2 %~3 %~4 %~5
) else (
    echo Compilation failed!
    pause
    exit /b 1
)

echo.
echo Press any key to exit...
pause > nul
