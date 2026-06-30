' ============================================================
'  Hidden launcher for scheduled task "Gemini Memory Backup".
'  Window mode 0 = hidden; wait until PowerShell finishes.
' ============================================================
Dim fso, here, shell
Set fso = CreateObject("Scripting.FileSystemObject")
here = fso.GetParentFolderName(WScript.ScriptFullName)
Set shell = CreateObject("WScript.Shell")
shell.Run "powershell.exe -NoProfile -ExecutionPolicy Bypass -File """ & here & "\backup-gemini-memory.ps1""", 0, True
