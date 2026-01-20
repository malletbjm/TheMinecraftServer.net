Set shell = CreateObject("WScript.Shell")
Set fso = CreateObject("Scripting.FileSystemObject")
scriptDir = fso.GetParentFolderName(WScript.ScriptFullName)
rootDir = fso.GetParentFolderName(scriptDir)
ps1Path = scriptDir & "\TheMinecraftServer.net Mods Installer.ps1"

' Best-effort: refresh shortcut icon to absolute path on this machine.
On Error Resume Next
linkPath = rootDir & "\TheMinecraftServer.net Mods Installer.lnk"
If fso.FileExists(linkPath) Then
    Set lnk = shell.CreateShortcut(linkPath)
    lnk.IconLocation = scriptDir & "\server-icon.ico,0"
    lnk.Save
End If
On Error GoTo 0

cmd = "powershell.exe -NoProfile -ExecutionPolicy Bypass -File """ & ps1Path & """"
shell.Run cmd, 1, False
