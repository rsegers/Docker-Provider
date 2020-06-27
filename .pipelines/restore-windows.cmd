echo "START:Adding and restoring dotnet packages"
cd /D "%~dp0..\build\windows\installer\certificategenerator"
dotnet add package Newtonsoft.json
dotnet add package BouncyCastle
dotnet restore CertificateGenerator.csproj
dotnet publish -c Release -r win10-x64
echo "END:Adding and restoring dotnet packages"

echo "START:set env vars to indicate this running on cdpx build machine"
setx IsCDPXBuildMachine "true"
set IsCDPXBuildMachine="true"
echo "END:set env vars to indicate this running on cdpx build machine"

echo "START:Getting go packages"
cd /D "%~dp0..\source\plugins\go\src"
go get
echo "END:Getting go packages"
