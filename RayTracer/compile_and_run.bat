@echo off
echo Setting up CUDA development environment...
call "C:\Program Files (x86)\Microsoft Visual Studio\2022\BuildTools\VC\Auxiliary\Build\vcvarsall.bat" x64

echo Navigating to source directory...
cd /d "%~dp0src"

echo Compiling CUDA program...
nvcc main.cu -o main.exe

if %ERRORLEVEL% EQU 0 (
    echo Compilation successful! Running program...
    echo.
    if "%1"=="" (
        main.exe
    ) else (
        main.exe "%1"
    )
) else (
    echo Compilation failed!
    pause
)

echo.
echo Press any key to exit...
pause > nul