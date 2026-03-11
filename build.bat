@echo off
setlocal enabledelayedexpansion
:: Name: build.bat
:: Version: v1.2.4
:: Author: bambosan
:: Date: 2026, 03, 11
:: Used for build final changes, not for development

REM Set root directory to current directory to avoid any file issues
pushd "%~dp0"

REM Colours and escape sequences (from matject, thanks to fzul)
set "GRY=[90m"
set "RED=[91m"
set "GRN=[92m"
set "YLW=[93m"
set "BLU=[94m"
set "CYN=[96m"
set "WHT=[97m"
set "RST=[0m" && REM Clears colours and formatting
set "ERR=[41;97m" && REM Red background with white text

REM Shaderc paths
set "SHADERC_PATH=shaderc.exe"
set "ZIP_FILE=shaderc.zip"
set "DOWNLOAD_URL=https://github.com/bambosan/bgfx-mcbe/releases/download/binaries/shaderc-win-x64.zip"

REM Materials paths
set "BASE_MATERIALS_PATH=pack\renderer\materials"
set "SUBPACKS_PATH=pack\subpacks"
set "VC_SUBPACK_MATERIALS_PATH=%SUBPACKS_PATH%\vc\renderer\materials"
set "NOVC_SUBPACK_MATERIALS_PATH=%SUBPACKS_PATH%\novc\renderer\materials"

REM checking platforms param
if "%~1"=="" (
    echo Usage: build.bat ^<platform^>
    echo Allowed: windows ^| android ^| ios
    popd
    exit /b 1
)
set "PLATFORM=%~1"

REM paramter/platform validatoin
if /I not "%PLATFORM%"=="windows" if /I not "%PLATFORM%"=="android" if /I not "%PLATFORM%"=="ios" (
    echo Invalid platform: %PLATFORM%
    echo Allowed platforms: windows, android, ios
    popd
    exit /b 1
)

REM Set build profiles
set "BASE_PROFILE=%PLATFORM%"
set "NORMAL_PROFILE=%PLATFORM% shading vclouds"
set "NOCLOUDS_PROFILE=%PLATFORM% shading"

REM Checking for lazurite
python -c "import lazurite" 2>nul
if errorlevel 1 (
    echo !ERR!Lazurite not found.!RST!
    echo !WHT!Make sure you have installed lazurite.!RST!
    echo !WHT!To install lazurite open a command prompt and run: !GRY!pip install lazurite!RST!
    popd
    exit /b 1
)
echo !GRN!Lazurite found!!RST!

REM Checking and downloading shaderc
if exist "%SHADERC_PATH%" (
    echo !GRN!Shaderc found!RST!
    goto :build_materials
) else (
    echo !RED!Shaderc not found!!RST!
    echo !YLW!Downloading shaderc...!RST!
    powershell -Command "Invoke-WebRequest -Uri '%DOWNLOAD_URL%' -OutFile '%ZIP_FILE%'"
    if errorlevel 1 (
        echo !ERR!Failed to download shaderc!RST!
        popd
        exit /b 1
    )
    powershell -Command "Expand-Archive -Force '%ZIP_FILE%' '.'" >nul
)

REM Make sure shaderc downloaded, extracted and renamed successfully
if exist "shadercRelease.exe" (
    move "shadercRelease.exe" "%SHADERC_PATH%" >nul
) else (
    echo !ERR!Shaderc binary not found after extraction!!RST!
    popd
    exit /b 1
)
del "%ZIP_FILE%"
echo;

:build_materials
REM Check for build output directories, create them if they don't exist
md "%BASE_MATERIALS_PATH%"
md "%VC_SUBPACK_MATERIALS_PATH%"
md "%NOVC_SUBPACK_MATERIALS_PATH%"

cls

REM Build all profiles for windows
echo !WHT!Running build profile: %BASE_PROFILE%!RST!
call python -m lazurite build ./src -p %BASE_PROFILE% -o "%BASE_MATERIALS_PATH%"
if errorlevel 1 (
    echo !ERR!Failed to build profile: %BASE_PROFILE%!RST!
    exit /b 1
)
echo;

echo !WHT!Running build profile: %NORMAL_PROFILE%!RST!
call python -m lazurite build ./src -p %NORMAL_PROFILE% -o "%VC_SUBPACK_MATERIALS_PATH%"
if errorlevel 1 (
    echo !ERR!Failed to build profile: %NORMAL_PROFILE%!RST!
    exit /b 1
)
echo;

echo !WHT!Running build profile: %NOCLOUDS_PROFILE%!RST!
call python -m lazurite build ./src -p %NOCLOUDS_PROFILE% -o "%NOVC_SUBPACK_MATERIALS_PATH%"
if errorlevel 1 (
    echo !ERR!Failed to build profile: %NOCLOUDS_PROFILE%!RST!
    exit /b 1
)
echo;

echo !GRN!All profiles builds completed successfully!!RST!
exit 0
