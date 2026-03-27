{
  inputs,
  self,
  ...
}: {
  perSystem = {pkgs, ...}: {
    packages = {
      noctalia-shell = inputs.wrapper-modules.wrappers.noctalia-shell.wrap {
        inherit pkgs;
        package = pkgs.noctalia-shell.overrideAttrs {
          name = "custom-noctalia";
        };
        env = {
          "NOCTALIA_CACHE_DIR" = "/tmp/noctalia-cache/";
        };
        extraPackages = with pkgs; [
          pwvucontrol
          wl-clipboard
          cliphist
        ];
        # TODO: use theme colors
        colors = {
          mError = "#c34043";
          mHover = "#7e9cd8";
          mOnError = "#1f1f28";
          mOnHover = "#1f1f28";
          mOnPrimary = "#1f1f28";
          mOnSecondary = "#1f1f28";
          mOnSurface = "#c8c093";
          mOnSurfaceVariant = "#717c7c";
          mOnTertiary = "#1f1f28";
          mOutline = "#363646";
          mPrimary = "#76946a";
          mSecondary = "#c0a36e";
          mShadow = "#1f1f28";
          mSurface = "#1f1f28";
          mSurfaceVariant = "#2a2a37";
          mTertiary = "#7e9cd8";
        };
        settings = {
          settingsVersion = 55;
          bar = {
            barType = "floating";
            position = "left";
            monitors = [];
            density = "spacious";
            showOutline = false;
            showCapsule = false;
            capsuleOpacity = 1;
            capsuleColorKey = "none";
            widgetSpacing = 6;
            contentPadding = 2;
            fontScale = 1;
            backgroundOpacity = 0.93;
            useSeparateOpacity = false;
            floating = true;
            marginVertical = 4;
            marginHorizontal = 4;
            frameThickness = 8;
            frameRadius = 12;
            outerCorners = true;
            hideOnOverview = false;
            displayMode = "always_visible";
            autoHideDelay = 500;
            autoShowDelay = 150;
            showOnWorkspaceSwitch = true;
            widgets = {
              left = [
                {
                  colorizeDistroLogo = false;
                  colorizeSystemIcon = "none";
                  customIconPath = "";
                  enableColorization = false;
                  icon = "noctalia";
                  id = "ControlCenter";
                  useDistroLogo = true;
                }
                {
                  colorizeIcons = false;
                  hideMode = "hidden";
                  id = "ActiveWindow";
                  maxWidth = 500;
                  scrollingMode = "hover";
                  showIcon = true;
                  textColor = "none";
                  useFixedWidth = false;
                }
                {
                  compactMode = false;
                  hideMode = "hidden";
                  hideWhenIdle = false;
                  id = "MediaMini";
                  maxWidth = 145;
                  panelShowAlbumArt = true;
                  scrollingMode = "hover";
                  showAlbumArt = true;
                  showArtistFirst = true;
                  showProgressRing = true;
                  showVisualizer = false;
                  textColor = "none";
                  useFixedWidth = false;
                  visualizerType = "linear";
                }
              ];
              center = [
                {
                  characterCount = 2;
                  colorizeIcons = false;
                  emptyColor = "secondary";
                  enableScrollWheel = true;
                  focusedColor = "primary";
                  followFocusedScreen = false;
                  groupedBorderOpacity = 1;
                  hideUnoccupied = true;
                  iconScale = 0.8;
                  id = "Workspace";
                  labelMode = "none";
                  occupiedColor = "secondary";
                  pillSize = 0.5;
                  showApplications = false;
                  showBadge = true;
                  showLabelsOnlyWhenOccupied = true;
                  unfocusedIconsOpacity = 1;
                }
              ];
              right = [
                {
                  compactMode = true;
                  diskPath = "/";
                  iconColor = "none";
                  id = "SystemMonitor";
                  showCpuCores = false;
                  showCpuFreq = false;
                  showCpuTemp = true;
                  showCpuUsage = true;
                  showDiskAvailable = false;
                  showDiskUsage = false;
                  showDiskUsageAsPercent = false;
                  showGpuTemp = false;
                  showLoadAverage = false;
                  showMemoryAsPercent = false;
                  showMemoryUsage = true;
                  showNetworkStats = false;
                  showSwapUsage = false;
                  textColor = "none";
                  useMonospaceFont = true;
                  usePadding = false;
                }
                {
                  displayMode = "onhover";
                  iconColor = "none";
                  id = "Volume";
                  middleClickCommand = "pwvucontrol";
                  textColor = "none";
                }
                {
                  displayMode = "onhover";
                  iconColor = "none";
                  id = "Microphone";
                  middleClickCommand = "pwvucontrol";
                  textColor = "none";
                }
                {
                  displayMode = "onhover";
                  iconColor = "none";
                  id = "Network";
                  textColor = "none";
                }
                {
                  displayMode = "onhover";
                  iconColor = "none";
                  id = "Bluetooth";
                  textColor = "none";
                }
                {
                  hideWhenZero = false;
                  hideWhenZeroUnread = false;
                  iconColor = "none";
                  id = "NotificationHistory";
                  showUnreadBadge = true;
                  unreadBadgeColor = "primary";
                }
                {
                  deviceNativePath = "__default__";
                  displayMode = "graphic-clean";
                  hideIfIdle = false;
                  hideIfNotDetected = true;
                  id = "Battery";
                  showNoctaliaPerformance = false;
                  showPowerProfiles = false;
                }
                {
                  clockColor = "none";
                  customFont = "";
                  formatHorizontal = "HH:mm";
                  formatVertical = "HH mm";
                  id = "Clock";
                  tooltipFormat = "HH:mm ddd, MMM dd";
                  useCustomFont = false;
                }
                {
                  blacklist = [];
                  chevronColor = "none";
                  colorizeIcons = false;
                  drawerEnabled = true;
                  hidePassive = false;
                  id = "Tray";
                  pinned = [];
                }
              ];
            };
            mouseWheelAction = "workspace";
            reverseScroll = false;
            mouseWheelWrap = true;
            middleClickAction = "launcherPanel";
            middleClickFollowMouse = false;
            middleClickCommand = "";
            rightClickAction = "controlCenter";
            rightClickFollowMouse = true;
            rightClickCommand = "";
            screenOverrides = [];
          };
          general = {
            avatarImage = "${self}/assets/face.png";
            dimmerOpacity = 0.2;
            showScreenCorners = true;
            forceBlackScreenCorners = true;
            scaleRatio = 1;
            radiusRatio = 1;
            iRadiusRatio = 1;
            boxRadiusRatio = 1;
            screenRadiusRatio = 1;
            animationSpeed = 1;
            animationDisabled = false;
            compactLockScreen = false;
            lockScreenAnimations = false;
            lockOnSuspend = true;
            showSessionButtonsOnLockScreen = true;
            showHibernateOnLockScreen = false;
            enableLockScreenMediaControls = true;
            enableShadows = true;
            shadowDirection = "bottom_right";
            shadowOffsetX = 2;
            shadowOffsetY = 3;
            language = "";
            allowPanelsOnScreenWithoutBar = true;
            showChangelogOnStartup = true;
            telemetryEnabled = false;
            enableLockScreenCountdown = true;
            lockScreenCountdownDuration = 10000;
            autoStartAuth = false;
            allowPasswordWithFprintd = false;
            clockStyle = "custom";
            clockFormat = "ddd MMM d ";
            passwordChars = true;
            lockScreenMonitors = [];
            lockScreenBlur = 0;
            lockScreenTint = 0;
            keybinds = {
              keyUp = ["Up"];
              keyDown = ["Down"];
              keyLeft = ["Left"];
              keyRight = ["Right"];
              keyEnter = ["Return" "Enter"];
              keyEscape = ["Esc"];
              keyRemove = ["Del"];
            };
            reverseScroll = false;
          };
          ui = {
            fontDefault = "JetBrains Mono";
            fontFixed = "JetBrains Mono";
            fontDefaultScale = 1;
            fontFixedScale = 1;
            tooltipsEnabled = true;
            boxBorderEnabled = false;
            panelBackgroundOpacity = 0.93;
            panelsAttachedToBar = true;
            settingsPanelMode = "attached";
            settingsPanelSideBarCardStyle = false;
          };
          location = {
            name = "Port of Spain, Trinidad";
            weatherEnabled = true;
            weatherShowEffects = true;
            useFahrenheit = true;
            use12hourFormat = false;
            showWeekNumberInCalendar = false;
            showCalendarEvents = true;
            showCalendarWeather = true;
            analogClockInCalendar = false;
            firstDayOfWeek = -1;
            hideWeatherTimezone = false;
            hideWeatherCityName = false;
          };
          calendar = {
            cards = [
              {
                enabled = true;
                id = "calendar-header-card";
              }
              {
                enabled = true;
                id = "calendar-month-card";
              }
              {
                enabled = true;
                id = "weather-card";
              }
            ];
          };
          wallpaper = {
            enabled = true;
            overviewEnabled = false;
            directory = "/home/aidanp/Pictures/Wallpapers";
            monitorDirectories = [];
            enableMultiMonitorDirectories = false;
            showHiddenFiles = false;
            viewMode = "single";
            setWallpaperOnAllMonitors = true;
            fillMode = "crop";
            fillColor = "#000000";
            useSolidColor = false;
            solidColor = "#1a1a2e";
            automationEnabled = false;
            wallpaperChangeMode = "random";
            randomIntervalSec = 300;
            transitionDuration = 1500;
            transitionType = "random";
            skipStartupTransition = false;
            transitionEdgeSmoothness = 0.05;
            panelPosition = "follow_bar";
            hideWallpaperFilenames = false;
            overviewBlur = 0.4;
            overviewTint = 0.6;
            useWallhaven = false;
            wallhavenQuery = "";
            wallhavenSorting = "relevance";
            wallhavenOrder = "desc";
            wallhavenCategories = "111";
            wallhavenPurity = "100";
            wallhavenRatios = "";
            wallhavenApiKey = "";
            wallhavenResolutionMode = "atleast";
            wallhavenResolutionWidth = "";
            wallhavenResolutionHeight = "";
            sortOrder = "name";
            favorites = [];
          };
          appLauncher = {
            enableClipboardHistory = true;
            autoPasteClipboard = false;
            enableClipPreview = true;
            clipboardWrapText = true;
            clipboardWatchTextCommand = "wl-paste --type text --watch cliphist store";
            clipboardWatchImageCommand = "wl-paste --type image --watch cliphist store";
            position = "center";
            pinnedApps = [];
            useApp2Unit = false;
            sortByMostUsed = true;
            terminalCommand = "ghostty -e";
            customLaunchPrefixEnabled = false;
            customLaunchPrefix = "";
            viewMode = "grid";
            showCategories = true;
            iconMode = "tabler";
            showIconBackground = false;
            enableSettingsSearch = true;
            enableWindowsSearch = true;
            enableSessionSearch = true;
            ignoreMouseInput = false;
            screenshotAnnotationTool = "";
            overviewLayer = false;
            density = "comfortable";
          };
          controlCenter = {
            position = "close_to_bar_button";
            diskPath = "/";
            shortcuts = {
              left = [
                {
                  id = "Network";
                }
                {
                  id = "Bluetooth";
                }
                {
                  id = "NoctaliaPerformance";
                }
              ];
              right = [
                {
                  id = "Notifications";
                }
                {
                  id = "KeepAwake";
                }
                {
                  id = "NightLight";
                }
              ];
            };
            cards = [
              {
                enabled = true;
                id = "profile-card";
              }
              {
                enabled = true;
                id = "shortcuts-card";
              }
              {
                enabled = true;
                id = "audio-card";
              }
              {
                enabled = false;
                id = "brightness-card";
              }
              {
                enabled = true;
                id = "weather-card";
              }
              {
                enabled = true;
                id = "media-sysmon-card";
              }
            ];
          };
          systemMonitor = {
            cpuWarningThreshold = 80;
            cpuCriticalThreshold = 90;
            tempWarningThreshold = 80;
            tempCriticalThreshold = 90;
            gpuWarningThreshold = 80;
            gpuCriticalThreshold = 90;
            memWarningThreshold = 80;
            memCriticalThreshold = 90;
            swapWarningThreshold = 80;
            swapCriticalThreshold = 90;
            diskWarningThreshold = 80;
            diskCriticalThreshold = 90;
            diskAvailWarningThreshold = 20;
            diskAvailCriticalThreshold = 10;
            batteryWarningThreshold = 20;
            batteryCriticalThreshold = 5;
            enableDgpuMonitoring = true;
            useCustomColors = false;
            warningColor = "";
            criticalColor = "";
            externalMonitor = "resources || missioncenter || jdsystemmonitor || corestats || system-monitoring-center || gnome-system-monitor || plasma-systemmonitor || mate-system-monitor || ukui-system-monitor || deepin-system-monitor || pantheon-system-monitor";
          };
          dock = {
            enabled = false;
            position = "bottom";
            displayMode = "auto_hide";
            dockType = "floating";
            backgroundOpacity = 1;
            floatingRatio = 1;
            size = 1;
            onlySameOutput = true;
            monitors = [];
            pinnedApps = [];
            colorizeIcons = false;
            showLauncherIcon = false;
            launcherPosition = "end";
            launcherIconColor = "none";
            pinnedStatic = false;
            inactiveIndicators = false;
            groupApps = false;
            groupContextMenuMode = "extended";
            groupClickAction = "cycle";
            groupIndicatorStyle = "dots";
            deadOpacity = 0.6;
            animationSpeed = 1;
            sitOnFrame = false;
            showDockIndicator = false;
            indicatorThickness = 3;
            indicatorColor = "primary";
            indicatorOpacity = 0.6;
          };
          network = {
            wifiEnabled = true;
            airplaneModeEnabled = false;
            bluetoothRssiPollingEnabled = false;
            bluetoothRssiPollIntervalMs = 60000;
            networkPanelView = "wifi";
            wifiDetailsViewMode = "grid";
            bluetoothDetailsViewMode = "grid";
            bluetoothHideUnnamedDevices = true;
            disableDiscoverability = false;
            bluetoothAutoConnect = true;
          };
          sessionMenu = {
            enableCountdown = true;
            countdownDuration = 10000;
            position = "center";
            showHeader = true;
            showKeybinds = true;
            largeButtonsStyle = true;
            largeButtonsLayout = "single-row";
            powerOptions = [
              {
                action = "lock";
                command = "";
                countdownEnabled = true;
                enabled = true;
                keybind = "1";
              }
              {
                action = "suspend";
                command = "";
                countdownEnabled = true;
                enabled = true;
                keybind = "2";
              }
              {
                action = "hibernate";
                command = "";
                countdownEnabled = true;
                enabled = true;
                keybind = "3";
              }
              {
                action = "reboot";
                command = "";
                countdownEnabled = true;
                enabled = true;
                keybind = "4";
              }
              {
                action = "logout";
                command = "";
                countdownEnabled = true;
                enabled = true;
                keybind = "5";
              }
              {
                action = "shutdown";
                command = "";
                countdownEnabled = true;
                enabled = true;
                keybind = "6";
              }
              {
                action = "userspaceReboot";
                command = "";
                countdownEnabled = true;
                enabled = false;
                keybind = "";
              }
              {
                action = "rebootToUefi";
                command = "";
                countdownEnabled = true;
                enabled = true;
                keybind = "";
              }
            ];
          };
          notifications = {
            enabled = true;
            enableMarkdown = false;
            density = "default";
            monitors = [];
            location = "top_right";
            overlayLayer = true;
            backgroundOpacity = 1;
            respectExpireTimeout = false;
            lowUrgencyDuration = 3;
            normalUrgencyDuration = 8;
            criticalUrgencyDuration = 15;
            clearDismissed = true;
            saveToHistory = {
              low = true;
              normal = true;
              critical = true;
            };
            sounds = {
              enabled = false;
              volume = 0.5;
              separateSounds = false;
              criticalSoundFile = "";
              normalSoundFile = "";
              lowSoundFile = "";
              excludedApps = "discord,firefox,chrome,chromium,edge";
            };
            enableMediaToast = false;
            enableKeyboardLayoutToast = true;
            enableBatteryToast = true;
          };
          osd = {
            enabled = true;
            location = "top_right";
            autoHideMs = 2000;
            overlayLayer = true;
            backgroundOpacity = 1;
            enabledTypes = [
              0
              1
              2
              3
            ];
            monitors = [];
          };
          audio = {
            volumeStep = 5;
            volumeOverdrive = false;
            cavaFrameRate = 30;
            visualizerType = "linear";
            mprisBlacklist = [];
            preferredPlayer = "mpv";
            volumeFeedback = false;
            volumeFeedbackSoundFile = "";
          };
          brightness = {
            brightnessStep = 5;
            enforceMinimum = true;
            enableDdcSupport = false;
            backlightDeviceMappings = [];
          };
          colorSchemes = {
            useWallpaperColors = false;
            predefinedScheme = "Monochrome";
            darkMode = true;
            schedulingMode = "off";
            manualSunrise = "06:30";
            manualSunset = "18:30";
            generationMethod = "tonal-spot";
            monitorForColors = "";
          };
          nightLight = {
            enabled = false;
            forced = false;
            autoSchedule = true;
            nightTemp = "4000";
            dayTemp = "6500";
            manualSunrise = "06:30";
            manualSunset = "18:30";
          };
          hooks = {
            enabled = false;
            wallpaperChange = "";
            darkModeChange = "";
            screenLock = "";
            screenUnlock = "";
            performanceModeEnabled = "";
            performanceModeDisabled = "";
            startup = "";
            session = "";
          };
          plugins.autoUpdate = false;
          idle.enabled = false;
          desktopWidgets.enabled = false;
        };
      };
    };
  };
}
