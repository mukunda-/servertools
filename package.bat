mkdir updater
mkdir updater\plugins
mkdir updater\scripting
mkdir updater\scripting\servertools
mkdir updater\docs

mkdir package
mkdir package\server
mkdir package\server\configs
mkdir package\server\plugins
mkdir package\server\docs
mkdir package\server\scripting
mkdir package\server\scripting\servertools
mkdir package\remote
mkdir package\stc
mkdir package\stc\win32

copy plugin\servertools.sp updater\scripting\ /Y
copy plugin\servertools\* updater\scripting\servertools\ /Y
copy plugin\servertools.smx updater\plugins\ /Y
copy docs\servertools3.txt updater\docs\ /Y

copy docs\servertools3.txt package\ /Y
copy docs\servertools3.txt package\server\docs /Y
copy plugin\servertools.smx package\server\plugins /Y
copy plugin\servertools.sp package\server\scripting /Y
copy plugin\servertools\* package\server\scripting\servertools\ /Y
copy servertools.cfg.example package\server\configs /Y
copy servertools_id.cfg.example package\server\configs /Y
copy web\listing.php package\remote /Y
copy web\setkey.php package\remote /Y
copy stc\autoexec_stock.cfg package\stc\win32\autoexec.cfg /Y
copy stc\Release\stc.exe package\stc\win32 /Y
copy stc\LICENSE_1_0.txt package\stc\win32 /Y


@echo off
echo ***
echo ***
echo *** don't forget to set version in servertools_update.txt ***
echo *** and compile smx! ***
echo ***
echo ***
echo (all done)
echo -----------------------

pause