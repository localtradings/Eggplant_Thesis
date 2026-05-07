@echo off
setlocal
set "PATH=C:\Program Files\Eclipse Adoptium\jdk-17.0.18.8-hotspot\bin;%PATH%"
set "ANDROID_SDK_ROOT=C:\Users\jross\AppData\Local\Android\Sdk"
cd /d C:\eggplant70-main-main\eggplant70-main-main
"C:\Users\jross\.gradle\wrapper\dists\gradle-8.9-bin\90cnw93cvbtalezasaz0blq0a\gradle-8.9\bin\gradle.bat" --no-daemon --console=plain installDebug --stacktrace
exit /b %ERRORLEVEL%
