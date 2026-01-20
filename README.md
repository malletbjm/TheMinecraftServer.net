# TheMinecraftServer.net Mods Installer

Windows installer for TheMinecraftServer.net Minecraft 1.21.7 mod pack. It bundles a PowerShell installer and an optional WinForms launcher to install Fabric, deploy the mod set, and tune launcher memory settings with a guided UI.

## Application process overview

1. Entry point and host selection:
   - If the PowerShell script is run directly and `TMS_HOST_UI` is not set to `gui`, it looks for `TheMinecraftServer.net Mods Installer.exe` beside the script (or its parent folder). If found, it launches the EXE and exits.
   - The EXE extracts embedded resources to a temp folder, sets `TMS_HOST_UI=gui`, and runs the PowerShell installer with `-NoProfile -ExecutionPolicy Bypass`. Output is piped into the custom UI, and "Press Enter" prompts in the script are satisfied by sending a newline to stdin.

2. UI initialization:
   - The script configures console colors, window size, icon, and banner text (best-effort), then waits for the user to continue.

3. Preflight checks:
   - Verifies Java is available on the PATH.
   - Verifies the Minecraft data directory exists at `%APPDATA%\.minecraft`.

4. Mods source preparation:
   - Clears and recreates a local `mods` staging folder.
   - If `TMS_MODS_URL` is set, downloads a zip to `%TEMP%` (optionally validated by `TMS_MODS_SHA256`), extracts it, and normalizes nested `mods\` folders.
   - Otherwise, queries GitHub releases (default repo `malletbjm/TheMinecraftServer.net`) and downloads matching assets, filtered by `TMS_MODS_TAG`, `TMS_MODS_FILTER`, and `TMS_MODS_EXTENSIONS` (default `.jar`).

5. Fabric installation:
   - Runs `Fabric Installer.jar` with `java -jar` targeting Minecraft `1.21.7`, installing the Fabric client into `%APPDATA%\.minecraft`.

6. Mods migration and install:
   - Ensures `%APPDATA%\.minecraft\mods` exists.
   - Moves existing mod files into `%APPDATA%\.minecraft\mods\Old mods\<version>`, where `<version>` is inferred from filenames (fallback to `1.21.7`).
   - Copies the staged mods into the active `mods` folder.

7. Launcher profile update:
   - Updates `%APPDATA%\.minecraft\launcher_profiles.json` for `fabric-loader-1.21.7`, ensuring `-Xmx` is set to one-third of system RAM (minimum 1 GB).

8. Completion:
   - Displays a success banner and exits after user confirmation.
