@echo off
REM Script to easily render OBJ files with the ray tracer
REM Usage: render_obj.bat path\to\model.obj

if "%1"=="" (
    echo Usage: render_obj.bat ^<path_to_obj_file^>
    echo.
    echo Example:
    echo   render_obj.bat models\cube.obj
    echo   render_obj.bat C:\path\to\my_model.obj
    exit /b 1
)

REM Get the absolute path of the OBJ file
for %%F in ("%1") do set OBJ_PATH=%%~dpnxF
for %%F in ("%1") do set OBJ_FULL=%%~fF

echo Attempting to load: %1
if not exist "%1" (
    REM Try relative to RayTracer directory
    if exist "models\%OBJ_FULL%" (
        set OBJ_PATH=%CD%\models\%OBJ_FULL%
    ) else (
        echo Error: OBJ file not found at %1
        exit /b 1
    )
) else (
    for %%F in ("%1") do set OBJ_PATH=%%~fF
)

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
    main.exe "%OBJ_PATH%"
) else (
    echo Compilation failed!
    pause
    exit /b 1
)

echo.
echo Press any key to exit...
pause > nul
