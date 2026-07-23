' ============================================================
'  隐藏窗口启动器 —— 由计划任务 OpenClaw Memory Backup 调用。
'  原任务有两个顺序动作：先 backup-memory，再 backup-openclaw。
'  这里保持同样顺序并且两项都尝试；最后传播首个非零退出码。
'  窗口模式 0 = 完全隐藏，不弹 PowerShell 窗、不抢前台焦点。
' ============================================================
Dim fso, here, shell, firstExitCode, exitCode
Set fso = CreateObject("Scripting.FileSystemObject")
here = fso.GetParentFolderName(WScript.ScriptFullName)
Set shell = CreateObject("WScript.Shell")
firstExitCode = shell.Run("powershell.exe -NoProfile -ExecutionPolicy Bypass -File """ & here & "\backup-memory.ps1""", 0, True)
exitCode = shell.Run("powershell.exe -NoProfile -ExecutionPolicy Bypass -File """ & here & "\backup-openclaw.ps1""", 0, True)
If firstExitCode <> 0 Then
    WScript.Quit firstExitCode
End If
WScript.Quit exitCode
