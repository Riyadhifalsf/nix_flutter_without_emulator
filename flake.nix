{
  description = "Flutter + Android SDK/NDK Dev Shell (no emulator, ready-to-use)";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";
    flake-utils.url = "github:numtide/flake-utils";
    android-nixpkgs = {
      url = "github:tadfisher/android-nixpkgs/main";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, flake-utils, android-nixpkgs }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs {
          inherit system;
          config = {
            allowUnfree = true;
            android_sdk.accept_license = true;
          };
        };

        stdenv = pkgs.stdenv;

        # Android SDK + NDK
        androidEnv = android-nixpkgs.sdk.${system} (sdkPkgs: with sdkPkgs; [
          cmdline-tools-latest
          build-tools-36-0-0
          platform-tools
          platforms-android-36
          ndk-28-2-13676358
        ]);

        # Patched Flutter derivation (fix cmake/ninja)
        patchedFlutter = pkgs.flutter.overrideAttrs (oldAttrs: {
          patchPhase = ''
            runHook prePatch
            substituteInPlace $FLUTTER_ROOT/packages/flutter_tools/gradle/src/main/kotlin/FlutterTask.kt \
              --replace 'val cmakeExecutable = project.file(cmakePath).absolutePath' 'val cmakeExecutable = "cmake"' \
              --replace 'val ninjaExecutable = project.file(ninjaPath).absolutePath' 'val ninjaExecutable = "ninja"'
            runHook postPatch
          '';
        });

        # Pin versions
        minSdkVersion = "21"; 
        kotlinVersion = "2.2.10";
        agpVersion = "9.4.0"; # Android Gradle Plugin
        ndkVersion = "28.2.13676358"

      in
      {
        devShells.default = (pkgs.buildFHSEnv {
          name = "FHS-flutter-android-dev-env-no-emulator";

          targetPkgs = pkgs: with pkgs; [
            bashInteractive
            git
            cmake
            ninja
            python3
            jdk17
            nix-ld
            gradle
            patchedFlutter
            androidEnv
            patchelf
            glibc
            zlib
            ncurses5
            stdenv.cc.cc.lib
            chromium
          ];

          multiPkgs = pkgs: with pkgs; [
            zlib
            ncurses5
            mesa
          ];

          profile = ''
              echo "FHS shell is active. Flutter + Android SDK/NDK environment setup..."

              export PATH="$FHS_LIB/usr/bin:$PATH"

              export NIX_LD_LIBRARY_PATH="${pkgs.lib.makeLibraryPath [
                pkgs.glibc
                pkgs.zlib
                pkgs.ncurses5
                stdenv.cc.cc.lib
              ]}"

              export LD_LIBRARY_PATH="$NIX_LD_LIBRARY_PATH:$LD_LIBRARY_PATH"

              # =========================
              # ANDROID SDK (PURE NIX)
              # =========================
              export ANDROID_HOME="${androidEnv}/share/android-sdk"
              export ANDROID_SDK_ROOT="$ANDROID_HOME"
              export ANDROID_NDK_HOME="$ANDROID_HOME/ndk/${ndkVersion}"

              export JAVA_HOME="${pkgs.jdk17}"

              export PATH="$ANDROID_HOME/platform-tools:${pkgs.cmake}/bin:${pkgs.ninja}/bin:$PATH"

              export CHROME_EXECUTABLE="${pkgs.chromium}/bin/chromium"

              # Flutter config (NO COPY)
              flutter config --android-sdk "$ANDROID_HOME" >/dev/null

              # =========================
              # CMake / Ninja bridge
              # =========================
              mkdir -p "$HOME/.android/cmake/3.22.1/bin"
              ln -sf "${pkgs.cmake}/bin/cmake" "$HOME/.android/cmake/3.22.1/bin/cmake"
              ln -sf "${pkgs.ninja}/bin/ninja" "$HOME/.android/cmake/3.22.1/bin/ninja"

              # =========================
              # Flutter project bootstrap
              # =========================
              if [ ! -f pubspec.yaml ]; then
                echo "No Flutter project found. Creating one..."
                flutter create .
                echo ".android/" >> .gitignore
              fi

              # Git init (safe)
              if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
                git init
                git add .
                git commit -m "Initial commit (Flutter + Nix dev shell)"
              fi

              # =========================
              # Gradle tuning (SAFE)
              # =========================
              mkdir -p android
              touch android/gradle.properties

              sed -i '/android\.cmake\./d' android/gradle.properties
              sed -i '/android\.ninja\./d' android/gradle.properties

              {
                echo "android.cmake.path=${pkgs.cmake}/bin"
                echo "android.cmake.makeProgram=${pkgs.ninja}/bin/ninja"
                echo "android.ndkVersion=${ndkVersion}"
              } >> android/gradle.properties

              flutter doctor --quiet

              echo "✅ Flutter + Android dev shell ready (PURE NIX, no emulator)"
              echo "👉 flutter build apk --release"
            '';
          runScript = "bash";
        }).env;
      });
}