#!/usr/bin/env node

import { execSync } from "node:child_process";
import { existsSync, mkdirSync, rmSync, writeFileSync, unlinkSync } from "node:fs";
import { homedir, platform } from "node:os";
import { join } from "node:path";
import https from "node:https";

const REPO = "DinN0000/DotBrain";
const APP_NAME = "DotBrain";
const APP_BUNDLE = `${APP_NAME}.app`;
const INSTALL_DIR = join(homedir(), "Applications");
const APP_PATH = join(INSTALL_DIR, APP_BUNDLE);
const EXECUTABLE = join(APP_PATH, "Contents", "MacOS", APP_NAME);
const LAUNCHAGENT_DIR = join(homedir(), "Library", "LaunchAgents");
const PLIST_NAME = "com.dotbrain.app";
const PLIST_PATH = join(LAUNCHAGENT_DIR, `${PLIST_NAME}.plist`);

// --- Helpers ---

function log(msg) {
  console.log(msg);
}

function error(msg) {
  console.error(`Error: ${msg}`);
  process.exit(1);
}

function run(cmd, opts = {}) {
  try {
    return execSync(cmd, { encoding: "utf8", stdio: opts.silent ? "pipe" : "inherit", ...opts });
  } catch {
    if (!opts.ignoreError) throw new Error(`Command failed: ${cmd}`);
    return "";
  }
}

function runSilent(cmd) {
  return run(cmd, { silent: true, ignoreError: true }).trim();
}

function httpsGet(url, maxRedirects = 5) {
  return new Promise((resolve, reject) => {
    const request = (reqUrl, remaining) => {
      if (remaining <= 0) {
        reject(new Error("Too many redirects"));
        return;
      }
      https.get(reqUrl, { headers: { "User-Agent": "dotbrain-cli" } }, (res) => {
        if (res.statusCode >= 300 && res.statusCode < 400 && res.headers.location) {
          request(res.headers.location, remaining - 1);
          return;
        }
        if (res.statusCode !== 200) {
          reject(new Error(`HTTP ${res.statusCode} for ${reqUrl}`));
          return;
        }
        const chunks = [];
        res.on("data", (chunk) => chunks.push(chunk));
        res.on("end", () => resolve(Buffer.concat(chunks)));
        res.on("error", reject);
      }).on("error", reject);
    };
    request(url, maxRedirects);
  });
}

async function downloadFile(url, dest) {
  const data = await httpsGet(url);
  writeFileSync(dest, data);
}

// --- Uninstall ---

function uninstall() {
  log("=== DotBrain 제거 ===\n");

  // Stop app
  runSilent("pkill -x DotBrain");

  // Unload LaunchAgent
  const uid = runSilent("id -u");
  runSilent(`launchctl bootout gui/${uid}/${PLIST_NAME}`);

  // Remove app
  if (existsSync(APP_PATH)) {
    rmSync(APP_PATH, { recursive: true, force: true });
    log(`Removed: ${APP_PATH}`);
  }

  // Remove LaunchAgent plist
  if (existsSync(PLIST_PATH)) {
    unlinkSync(PLIST_PATH);
    log(`Removed: ${PLIST_PATH}`);
  }

  log("\nDotBrain has been uninstalled.");
  process.exit(0);
}

// --- Install via DMG ---

async function installFromDmg(dmgUrl, tag) {
  const tmpDir = runSilent("mktemp -d");
  let activeMountPoint = null;

  try {
    const dmgPath = join(tmpDir, `${APP_NAME}.dmg`);

    log(`Downloading DMG (${tag})...`);
    await downloadFile(dmgUrl, dmgPath);

    // Mount DMG
    log("Mounting DMG...");
    const mountOutput = runSilent(`hdiutil attach "${dmgPath}" -nobrowse -readonly`);
    const parsedMount = mountOutput.split("\n").pop().split("\t").pop().trim();

    if (parsedMount && existsSync(join(parsedMount, APP_BUNDLE))) {
      activeMountPoint = parsedMount;
    } else {
      // Try finding the mount point
      const volumes = runSilent("ls /Volumes").split("\n");
      const dotbrainVol = volumes.find((v) => v.includes(APP_NAME));
      if (!dotbrainVol) {
        error("Failed to mount DMG or find DotBrain.app inside it.");
      }
      activeMountPoint = `/Volumes/${dotbrainVol}`;
    }

    return copyFromMount(activeMountPoint);
  } finally {
    // Unmount DMG if still mounted
    if (activeMountPoint) {
      runSilent(`hdiutil detach "${activeMountPoint}" -quiet`);
    }
    runSilent(`rm -rf "${tmpDir}"`);
  }
}

function copyFromMount(mountPoint) {
  const srcApp = join(mountPoint, APP_BUNDLE);

  if (!existsSync(srcApp)) {
    error(`${APP_BUNDLE} not found in DMG.`);
  }

  // Stop running instance
  const uid = runSilent("id -u");
  runSilent(`launchctl bootout gui/${uid}/${PLIST_NAME}`);
  runSilent("pkill -x DotBrain");
  runSilent("sleep 1");

  // Copy to ~/Applications
  mkdirSync(INSTALL_DIR, { recursive: true });
  if (existsSync(APP_PATH)) {
    rmSync(APP_PATH, { recursive: true, force: true });
  }
  run(`cp -R "${srcApp}" "${APP_PATH}"`, { silent: true });

  // Remove quarantine
  runSilent(`xattr -cr "${APP_PATH}"`);

  log(`Installed: ${APP_PATH}`);
  return true;
}

// --- Install via binary (fallback for older releases) ---

async function installFromBinary(binaryUrl, iconUrl, tag) {
  log(`Downloading binary (${tag})...`);

  const tmpDir = runSilent("mktemp -d");

  try {
    const binaryPath = join(tmpDir, APP_NAME);
    await downloadFile(binaryUrl, binaryPath);
    execSync(`chmod +x "${binaryPath}"`);

    // Stop running instance
    const uid = runSilent("id -u");
    runSilent(`launchctl bootout gui/${uid}/${PLIST_NAME}`);
    runSilent("pkill -x DotBrain");
    runSilent("sleep 1");

    // Assemble .app bundle
    mkdirSync(INSTALL_DIR, { recursive: true });
    if (existsSync(APP_PATH)) {
      rmSync(APP_PATH, { recursive: true, force: true });
    }

    const macosDir = join(APP_PATH, "Contents", "MacOS");
    const resourcesDir = join(APP_PATH, "Contents", "Resources");
    mkdirSync(macosDir, { recursive: true });
    mkdirSync(resourcesDir, { recursive: true });

    execSync(`cp "${binaryPath}" "${EXECUTABLE}"`);

    // Download icon
    if (iconUrl) {
      try {
        const iconPath = join(tmpDir, "AppIcon.icns");
        await downloadFile(iconUrl, iconPath);
        execSync(`cp "${iconPath}" "${join(resourcesDir, "AppIcon.icns")}"`);
      } catch {
        log("Warning: Icon download failed, continuing with default icon.");
      }
    }

    // Generate Info.plist
    const version = tag.replace(/^v/, "");
    const plistContent = `<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>
    <string>DotBrain</string>
    <key>CFBundleDisplayName</key>
    <string>DotBrain</string>
    <key>CFBundleIdentifier</key>
    <string>com.hwaa.dotbrain</string>
    <key>CFBundleVersion</key>
    <string>${version}</string>
    <key>CFBundleShortVersionString</key>
    <string>${version}</string>
    <key>CFBundleExecutable</key>
    <string>DotBrain</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>LSUIElement</key>
    <true/>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>NSAppTransportSecurity</key>
    <dict>
        <key>NSAllowsArbitraryLoads</key>
        <false/>
        <key>NSExceptionDomains</key>
        <dict>
            <key>api.anthropic.com</key>
            <dict>
                <key>NSExceptionAllowsInsecureHTTPLoads</key>
                <false/>
                <key>NSIncludesSubdomains</key>
                <true/>
            </dict>
        </dict>
    </dict>
</dict>
</plist>`;
    writeFileSync(join(APP_PATH, "Contents", "Info.plist"), plistContent);

    // Remove quarantine
    runSilent(`xattr -cr "${APP_PATH}"`);

    log(`Installed: ${APP_PATH}`);
  } finally {
    runSilent(`rm -rf "${tmpDir}"`);
  }
}

// --- LaunchAgent setup ---

function setupLaunchAgent() {
  log("\nSetting up auto-start (LaunchAgent)...");

  mkdirSync(LAUNCHAGENT_DIR, { recursive: true });

  const plistContent = `<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>${PLIST_NAME}</string>
    <key>ProgramArguments</key>
    <array>
        <string>${EXECUTABLE}</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <dict>
        <key>SuccessfulExit</key>
        <false/>
    </dict>
    <key>ProcessType</key>
    <string>Interactive</string>
</dict>
</plist>`;

  writeFileSync(PLIST_PATH, plistContent);

  const uid = runSilent("id -u");
  runSilent(`launchctl bootstrap gui/${uid} "${PLIST_PATH}"`);
  log("Auto-start registered.");
}

// --- Launch app ---

function launchApp() {
  log("\nStarting DotBrain...");
  const uid = runSilent("id -u");
  runSilent(`launchctl kickstart gui/${uid}/${PLIST_NAME}`);
  // Verify process is running; fallback to open if not
  runSilent("sleep 1");
  if (!runSilent(`pgrep -x ${APP_NAME}`)) {
    run(`open "${APP_PATH}"`, { silent: true, ignoreError: true });
  }
}

// --- Main ---

async function main() {
  // macOS check
  if (platform() !== "darwin") {
    error("DotBrain is a macOS application. It is not supported on this platform.");
  }

  const args = process.argv.slice(2);

  // Uninstall
  if (args.includes("--uninstall") || args.includes("-u")) {
    uninstall();
    return;
  }

  log("=== DotBrain Installer ===\n");

  const arch = runSilent("uname -m");
  const osVer = runSilent("sw_vers -productVersion");
  log(`System: macOS ${osVer} (${arch})\n`);

  // Fetch latest release
  log("Fetching latest release...");
  let releaseData;
  try {
    const raw = await httpsGet(`https://api.github.com/repos/${REPO}/releases/latest`);
    releaseData = JSON.parse(raw.toString());
  } catch (e) {
    error(`Failed to fetch release info: ${e.message}\nVisit https://github.com/${REPO}/releases to download manually.`);
  }

  const tag = releaseData.tag_name;
  if (!tag) {
    error("Could not determine release version.");
  }
  log(`Latest: ${tag}\n`);

  const assets = releaseData.assets || [];

  // Look for DMG first
  const dmgAsset = assets.find((a) => a.name.endsWith(".dmg"));
  const binaryAsset = assets.find((a) => a.name === APP_NAME);
  const iconAsset = assets.find((a) => a.name === "AppIcon.icns");

  if (dmgAsset) {
    await installFromDmg(dmgAsset.browser_download_url, tag);
  } else if (binaryAsset) {
    log("DMG not found, falling back to binary install...");
    await installFromBinary(
      binaryAsset.browser_download_url,
      iconAsset?.browser_download_url,
      tag
    );
  } else {
    error(`No installable assets found in release ${tag}.\nVisit https://github.com/${REPO}/releases to download manually.`);
  }

  setupLaunchAgent();
  launchApp();

  log(`
================================================
  Installation complete!
  Look for the dot-brain icon in your menu bar.

  - App location: ~/Applications
  - Auto-starts on login
  - Auto-restarts on crash
================================================

To uninstall:
  npx dotbrain --uninstall
`);
}

main().catch((e) => {
  error(e.message);
});
