============================================================
  Codename CURE - 32 Player Client Patch
============================================================

What this patch does:
  - Removes the hardcoded 5-player limit on the client side
  - Adds setinfo "cure_patched" "1" to config.cfg
    (so the server knows you have the patch)
  - Lets you join servers running 32-player mode

------------------------------------------------------------
INSTALLATION
------------------------------------------------------------

1. Make sure client.dll and Install.bat are in the same folder.

2. Double-click Install.bat

3. Choose [1] Install patch

4. The script will:
   a) Auto-detect your CURE install path
   b) Backup original client.dll as client.dll.original
   c) Copy patched client.dll to cure/bin/
   d) Add setinfo "cure_patched" "1" to cure/cfg/config.cfg

5. Done! Launch CURE and join a 32-player server.

------------------------------------------------------------
WHY config.cfg INSTEAD OF autoexec.cfg?
------------------------------------------------------------

CURE does not execute autoexec.cfg at startup.
config.cfg is the engine's core config file and is always loaded.
The setinfo line is written directly into config.cfg so it runs
automatically every time the game starts.

You do NOT need to type anything in the console manually.

------------------------------------------------------------
RESTORE ORIGINAL
------------------------------------------------------------

1. Run Install.bat
2. Choose [2] Restore original
3. client.dll is restored from backup
4. cure_patched line is removed from config.cfg

------------------------------------------------------------
TROUBLESHOOTING
------------------------------------------------------------

Q: Install.bat says "Game is running!"
A: Close CURE completely, then try again.

Q: Install.bat can't find the game path
A: Choose [3] Detect, then enter the path manually.
   Typical path: C:\Program Files (x86)\Steam\steamapps\
                 common\Codename CURE\cure\bin

Q: Server says "Patch Required" and kicks me
A: Your config.cfg doesn't have the setinfo line.
   Run Install.bat again, or manually type in console:
   setinfo cure_patched 1

Q: Game crashes on join
A: Make sure you're using the matching client.dll for your
   game version. Ask the server admin for the correct patch.

------------------------------------------------------------
FILES
------------------------------------------------------------

client.dll   - Patched client binary (32-player unlock)
Install.bat  - Installer script (auto-detect, backup, patch)
README.txt   - This file
