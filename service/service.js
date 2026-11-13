'use strict';
var Service = require('/usr/lib/node_modules/webos-service');
var cp = require('child_process');
var fs = require('fs');
var path = require('path');

var LAUNCHER_APP_ID = 'au.com.kellogs12.dumblg.launcher';
var SERVICE_ID = 'au.com.kellogs12.dumblg.service';
var BASE_SERVICE_DIR = '/media/developer/apps/usr/palm/services/' + SERVICE_ID;
var STATE_DIR = BASE_SERVICE_DIR + '/state';
var LEGACY_STATE_DIR = '/media/developer/apps/usr/palm/applications/com.local.nativehome/state';
var RELAY_BIN = BASE_SERVICE_DIR + '/bin/relay';

var REMOVED_APPS = [
  'com.pplus.webapp.prod-intl',
  'com.disney.disneyplus-prod',
  'com.streamotion.binge',
  'com.foxtel.app',
  'stan.webos2',
  'com.apple.appletv',
  'com.streamotion.kayosports',
  'au.com.optus.sport.lgtv',
  'tv.twitch.tv.starshot.lg',
  'googleplaymovieswebos'
];

process.on('uncaughtException', function(err) {
  console.error('[DumbLG] Uncaught exception:', (err && err.stack) || err);
});

var service = new Service(SERVICE_ID);
service.activityManager.create('dumblg-keepalive', function() {});

try {
  fs.writeFileSync(BASE_SERVICE_DIR + '/service.pid', String(process.pid));
} catch (e) {}

var relayProcess = null;
var pingTimer = null;
var relayRestartTimer = null;

function isEmergencyExit() {
  return fs.existsSync(LEGACY_STATE_DIR + '/watchdog') ||
         fs.existsSync(LEGACY_STATE_DIR + '/blocked') ||
         fs.existsSync(STATE_DIR + '/watchdog') ||
         fs.existsSync(STATE_DIR + '/blocked');
}

function applyLiveSettings() {
  console.log('[DumbLG] Applying live settings via Luna...');
  service.call('luna://com.webos.settingsservice/setSystemSettings', {
    category: 'option',
    settings: {
      livePlus: 'off',
      quickStartMode: 'off'
    }
  }, function(res) {
    console.log('[DumbLG] option settings result:', JSON.stringify(res.payload));
  });

  service.call('luna://com.webos.settingsservice/setSystemSettings', {
    category: 'general',
    settings: {
      homePromotion: 'off',
      homeAutoLaunch: 'off',
      screenSaverAd: 'off',
      adCookie: 'off',
      aiNudge: 'off'
    }
  }, function(res) {
    console.log('[DumbLG] general settings result:', JSON.stringify(res.payload));
  });
}

function applyHostsBlocklist() {
  try {
    var hosts = '';
    try { hosts = fs.readFileSync('/etc/hosts', 'utf8'); } catch (e) {}
    if (hosts.indexOf('DUMBTV-WEBOS-BLOCKLIST') === -1) {
      console.log('[DumbLG] Mounting /tmp/hosts and applying blocklist...');
      var cmd = 'if ! mount | grep -q " on /etc/hosts "; then cp /etc/hosts /tmp/hosts && mount --bind /tmp/hosts /etc/hosts; fi && cat >> /etc/hosts << "HOSTS"\n\n# --- DUMBTV-WEBOS-BLOCKLIST ---\n127.0.0.1 ad.lgappstv.com lgsmartad.com ngfts.lgsmartad.com\n127.0.0.1 ibis.lgappstv.com us.ibs.lgappstv.com kr.ibs.lgappstv.com\n127.0.0.1 eic.lgtvsdp.com ad.lgsmartserver.com smartshare.lgtvsdp.com\n127.0.0.1 livepluszz.lgtvsdp.com lgacr.com\n127.0.0.1 info.lgsmartad.com kr.info.lgsmartad.com ca.info.lgsmartad.com\n127.0.0.1 rdx2.lgtvsdp.com lgnoti.lgtvsdp.com kr.lgtvsdp.com\n127.0.0.1 kr.coredata.lgsmartserver.com us.coredata.lgsmartserver.com\n127.0.0.1 softwareupdates.amazon.com arcus-uswest.amazon.com\n127.0.0.1 unagi-na.amazon.com api.amazonalexa.com\nHOSTS\n';
      cp.exec(cmd, function(err) {
        if (err) console.error('[DumbLG] hosts block error:', err);
        else console.log('[DumbLG] hosts blocklist active');
      });
    } else {
      console.log('[DumbLG] hosts blocklist already present');
    }
  } catch (e) {
    console.error('[DumbLG] error reading /etc/hosts:', e);
  }
}

function removeBloatwareApps() {
  console.log('[DumbLG] Running bloatware app removal pass...');
  var targets = [];
  for (var i = 0; i < REMOVED_APPS.length; i++) {
    var appId = REMOVED_APPS[i];
    targets.push('/media/cryptofs/apps/usr/palm/applications/' + appId);
    targets.push('/media/cryptofs/apps/usr/palm/services/' + appId + '.*');
  }
  try {
    cp.exec('rm -rf ' + targets.join(' ') + ' 2>/dev/null', function(err) {
      if (err) console.error('[DumbLG] bloatware removal error:', err);
    });
  } catch (e) {
    console.error('[DumbLG] failed to spawn bloatware removal:', e);
  }
}

function launchDumbLG() {
  console.log('[DumbLG] Launching launcher:', LAUNCHER_APP_ID);
  service.call('luna://com.webos.applicationManager/launch', {
    id: LAUNCHER_APP_ID
  }, function(res) {
    console.log('[DumbLG] launch result:', JSON.stringify(res.payload));
  });
}

function startRelay() {
  if (isEmergencyExit()) {
    console.log('[DumbLG] Emergency exit latch active; relay will not start.');
    return;
  }
  if (!fs.existsSync(RELAY_BIN)) {
    console.error('[DumbLG] Relay binary not found at:', RELAY_BIN);
    return;
  }

  try {
    if (!fs.existsSync(STATE_DIR)) cp.execSync('mkdir -p "' + STATE_DIR + '"');
    var legacyParent = path.dirname(LEGACY_STATE_DIR);
    if (!fs.existsSync(legacyParent)) cp.execSync('mkdir -p "' + legacyParent + '"');
    if (!fs.existsSync(LEGACY_STATE_DIR)) {
      try { fs.symlinkSync(STATE_DIR, LEGACY_STATE_DIR); } catch (e) {}
    }
    // Remove stale lock
    try { fs.unlinkSync(STATE_DIR + '/relay.lock'); } catch (e) {}
    try { fs.unlinkSync(LEGACY_STATE_DIR + '/relay.lock'); } catch (e) {}
  } catch (e) {
    console.log('[DumbLG] state dir prep notice:', e.message);
  }

  console.log('[DumbLG] Spawning relay process:', RELAY_BIN);
  relayProcess = cp.spawn(RELAY_BIN, [], { stdio: ['pipe', 'pipe', 'pipe'] });

  relayProcess.stdout.on('data', function(chunk) {
    var lines = chunk.toString().split('\n');
    for (var i = 0; i < lines.length; i++) {
      var line = lines[i].trim();
      if (!line || line === 'P') continue;
      console.log('[Relay]', line);
      if (line === 'HOME') {
        launchDumbLG();
      }
    }
  });

  relayProcess.stderr.on('data', function(chunk) {
    console.error('[Relay err]', chunk.toString().trim());
  });

  relayProcess.on('exit', function(code) {
    console.log('[DumbLG] Relay exited with code:', code);
    relayProcess = null;
    if (pingTimer) {
      clearInterval(pingTimer);
      pingTimer = null;
    }

    if (isEmergencyExit()) {
      console.log('[DumbLG] Emergency latch triggered. LG Home is restored.');
      return;
    }

    if (!relayRestartTimer) {
      relayRestartTimer = setTimeout(function() {
        relayRestartTimer = null;
        startRelay();
      }, 2000);
    }
  });

  function sendPing() {
    if (relayProcess && relayProcess.stdin && !relayProcess.killed) {
      try { relayProcess.stdin.write('P\n'); } catch (e) {}
    }
  }
  sendPing();
  pingTimer = setInterval(sendPing, 800);
}

function monitorForeground() {
  try {
    service.subscribe('luna://com.webos.applicationManager/getForegroundAppInfo', {}, function(message) {
      if (message.payload && message.payload.returnValue !== false) {
        var currApp = message.payload.appId;
        if ((currApp === 'com.webos.app.home' || currApp === 'com.webos.app.fullhome') && !isEmergencyExit()) {
          console.log('[DumbLG] LG Home detected in foreground; redirecting to DumbLG');
          launchDumbLG();
        }
      }
    });
  } catch (e) {
    console.error('[DumbLG] Error subscribing to getForegroundAppInfo:', e);
  }
}

// Register service methods
service.register('status', function(message) {
  message.respond({
    returnValue: true,
    service: SERVICE_ID,
    nodeVersion: process.version,
    pid: process.pid,
    relayPid: relayProcess ? relayProcess.pid : null,
    emergency: isEmergencyExit(),
    time: Date.now()
  });
});

service.register('applySettings', function(message) {
  applyLiveSettings();
  applyHostsBlocklist();
  removeBloatwareApps();
  message.respond({ returnValue: true, message: 'Settings and debloat applied' });
});

service.register('launchHome', function(message) {
  launchDumbLG();
  message.respond({ returnValue: true, message: 'Launcher triggered' });
});

service.register('resetEmergency', function(message) {
  try { fs.unlinkSync(LEGACY_STATE_DIR + '/watchdog'); } catch (e) {}
  try { fs.unlinkSync(LEGACY_STATE_DIR + '/blocked'); } catch (e) {}
  try { fs.unlinkSync(STATE_DIR + '/watchdog'); } catch (e) {}
  try { fs.unlinkSync(STATE_DIR + '/blocked'); } catch (e) {}
  if (!relayProcess) {
    startRelay();
  }
  message.respond({ returnValue: true, message: 'Emergency exit reset; relay restarted' });
});

// Launcher pulls its app grid from this method (see launcher/app-library.js).
// Returns { returnValue, apps, installedIds } shaped to match that caller.
service.register('listApps', function(message) {
  console.log('[DumbLG] listApps called');
  service.call('luna://com.webos.applicationManager/listLaunchPoints', {}, function(res) {
    if (!res || !res.payload || !res.payload.returnValue) {
      var errMsg = (res && res.payload && (res.payload.errorText || res.payload.message)) || 'Failed to retrieve launch points';
      console.error('[DumbLG] listApps error:', errMsg);
      message.respond({ returnValue: false, error: errMsg, apps: [], installedIds: [] });
      return;
    }
    var points = res.payload.launchPoints || [];
    console.log('[DumbLG] listApps: got ' + points.length + ' launchPoints');
    var apps = [];
    var ids = [];
    for (var i = 0; i < points.length; i++) {
      var lp = points[i];
      // skip DumbLG itself so it doesn't appear as a tile on its own home
      if (lp.id === LAUNCHER_APP_ID) continue;
      apps.push({
        id: lp.id,
        title: lp.title || lp.id,
        icon: lp.icon || lp.largeIcon || lp.mediumLargeIcon || '',
        largeIcon: lp.largeIcon || lp.icon || '',
        appId: lp.id,
        launchPointId: lp.launchPointId,
        removable: !!lp.removable,
        systemApp: !!lp.systemApp
      });
      ids.push(lp.id);
    }
    message.respond({ returnValue: true, apps: apps, installedIds: ids });
  });
});

service.register('reboot', function(message) {
  message.respond({ returnValue: true, message: 'Rebooting...' });
  service.call('luna://com.webos.service.sleep/shutdown/machineReboot', {
    reason: 'remoteKey'
  }, function() {});
});

// Boot sequences
applyLiveSettings();
removeBloatwareApps();
setTimeout(removeBloatwareApps, 60000); // 60s second pass

startRelay();
monitorForeground();

console.log('[DumbLG] au.com.kellogs12.dumblg.service started with PID:', process.pid);
