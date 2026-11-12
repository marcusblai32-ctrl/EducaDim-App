; Installateur Windows d'EducaDim (compilé par le workflow GitHub avec Inno Setup).
[Setup]
AppName=EducaDim
AppVersion=1.0.0
AppPublisher=Dimension Production
DefaultDirName={autopf}\EducaDim
DefaultGroupName=EducaDim
OutputDir=..\..\dist
OutputBaseFilename=EducaDim-Setup
SetupIconFile=..\..\windows\runner\resources\app_icon.ico
UninstallDisplayIcon={app}\educadim.exe
Compression=lzma2
SolidCompression=yes
ArchitecturesInstallIn64BitMode=x64compatible
WizardStyle=modern
DisableProgramGroupPage=yes

[Languages]
Name: "french"; MessagesFile: "compiler:Languages\French.isl"

[Tasks]
Name: "desktopicon"; Description: "Créer une icône sur le Bureau"; GroupDescription: "Raccourcis :"

[Files]
Source: "..\..\build\windows\x64\runner\Release\*"; DestDir: "{app}"; Flags: recursesubdirs createallsubdirs ignoreversion

[Icons]
Name: "{group}\EducaDim"; Filename: "{app}\educadim.exe"
Name: "{autodesktop}\EducaDim"; Filename: "{app}\educadim.exe"; Tasks: desktopicon

[Run]
Filename: "{app}\educadim.exe"; Description: "Lancer EducaDim"; Flags: nowait postinstall skipifsilent
