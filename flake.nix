{
  outputs = { self, nixpkgs }:
    let
      system = "x86_64-linux";
    in
    rec {
      # replace '.' in strings with '_'
      lib.replaceDots = s: builtins.replaceStrings [ "." ] [ "_" ] s;

      # build an XNG OPS from a tarball release
      lib.buildXngOps = { pkgs, version ? "1.4", src ? null, srcs ? null, pname ? "xng-ops", target ? "armv7a-vmsa-tz" }:
        let
          archDefine = builtins.replaceStrings [ "-" ] [ "_" ] (pkgs.lib.toUpper target);
        in
        pkgs.stdenv.mkDerivation {
          inherit pname src srcs version;

          nativeBuildInputs = [ pkgs.autoPatchelfHook ];
          buildInputs = with pkgs; [
            (python3.withPackages (pythonPackages: with pythonPackages; [ lxml ]))
            libxml2
          ];

          outputs = [ "bin" "dev" "out" ];

          setupHook = pkgs.writeTextFile {
            name = "xngSetupHook";
            text = ''
              addXngFlags () {
                # make XNG headers discoverable
                for dir in "$1/lib/include" "$1/include/xc" "$1/include/xre-${target}"; do
                    if [ -d "$dir" ]; then
                        export NIX_CFLAGS_COMPILE+=" -isystem $dir"
                    fi
                done

                # export flags relevant to XNG
                export XNG_TARGET_CFLAGS="-ffreestanding -mabi=aapcs -mlittle-endian -march=armv7-a \
                    -mtune=cortex-a9 -mfpu=neon -DNEON -D${archDefine} -Wall -Wextra -pedantic -std=c99 \
                    -fno-builtin -O2 -fno-short-enums -mthumb"

                export TARGET_CFLAGS="$XNG_TARGET_CFLAGS"
                export TARGET_CC="$CC"
              }
              addEnvHooks "$hostOffset" addXngFlags
            '';
          };


          installPhase = ''
            runHook preInstall

            mkdir $bin $dev $out
            cp -r bin xsd.${target} $bin/
            cp -r cfg lds lib xre-examples $dev/
            cp -r * $out/

            runHook postInstall
          '';

          # meta attributes
          meta = {
            inherit target;
          };
        };

      # build an SKE OPS from a tarball release
      lib.buildSkeOps = { pkgs, src ? null, srcs ? null, name ? "ske-ops", target ? "skelinux" }:
        let
          archDefine = builtins.replaceStrings [ "-" ] [ "_" ] (pkgs.lib.toUpper target);
        in
        pkgs.stdenv.mkDerivation {
          inherit name src srcs;

          nativeBuildInputs = [ pkgs.autoPatchelfHook ];
          buildInputs = with pkgs; [
            (python2.withPackages (pythonPackages: with pythonPackages; [ lxml ]))
            libxml2
          ];

          outputs = [ "bin" "dev" "out" ];

          setupHook = pkgs.writeTextFile {
            name = "skeSetupHook";
            text = ''
              addSKEFlags () {
                # export flags relevant to SKE
                export SKE_TARGET_CFLAGS+=" -finstrument-functions -std=c99"
              }
              addEnvHooks "$hostOffset" addSKEFlags
            '';
          };

          installPhase = ''
            runHook preInstall

            mkdir $bin $dev $out
            cp -r bin $bin/
            cp -r lib examples $dev/
            cp -r * $out/

            runHook postInstall
          '';

          # meta attributes
          meta = {
            inherit target;
          };
        };

      # build a LithOS OPS
      lib.buildLithOsOps = { pkgs, src, version ? "1.0", pname ? "lithos-ops", patches ? [ ] }: pkgs.stdenvNoCC.mkDerivation {
        inherit patches pname src version;

        dontStrip = true;
        dontPatchELF = true;
        installPhase = ''
          runHook preInstall
          mkdir $out
          mv * $out
          runHook postInstall
        '';
      };

      # lib.buildPartitionC =
      #   { pkgs
      #   , xns-ops
      #   , name
      #   , entryPoint
      #   , src ? null
      #   , srcs ? null
      #   , hardFp ? false
      #   , stdenv ? (if hardFp then
      #       pkgs.pkgsCross.armhf-embedded.stdenv
      #     else pkgs.pkgsCross.arm-embedded.stdenv)
      #   }: {
      #     buildPhase = ''
      #       # find main
      #       set -x
      #       $CC $src -c -o Partition0.armv7a-vmsa-tz.o partition0.c
      #       $LD -EL ''${object_code[@]} -o ${name}.${target}.elf -Ttext
      #       $OBJCOPY -O binary ${name}.${target}.elf ${name}.${target}.bin
      #       { set +x; } 2>/dev/null
      #     '';
      #     installPhase = ''
      #       mkdir $out
      #       mv *.elf *.o $out/
      #     '';
      #     dontCHeck = true;
      #     dontFixup = true;
      #   };


      lib.load-xml = { pkgs, file }: builtins.fromJSON (builtins.readFile (pkgs.runCommandNoCC "convert-xml-to-json" { }
        "${pkgs.dasel}/bin/dasel --file ${file} --write json > $out"));

      lib.parse-xcf = { pkgs, src }:
        let
          parsed-xml = self.lib.load-xml { inherit pkgs; file = src + "/module.xml"; };
          pathToXml = attribute: old: (self.lib.load-xml { inherit pkgs; file = src + "/${old."-hRef"}"; }).${attribute};
          maybeListToList = old: if (builtins.typeOf old != "list") then [ old ] else old;
          merged = pkgs.lib.updateManyAttrsByPath [
            {
              path = [ "Module" "Channels" ];
              update = pathToXml "Channels";
            }
            {
              path = [ "Module" "Hypervisor" ];
              update = pathToXml "Hypervisor";
            }
            {
              path = [ "Module" "MultiPartitionHMTables" ];
              update = pathToXml "MultiPartitionHmTables"; # Why is the case different between both?!!
            }
            {
              path = [ "Module" "Partitions" ];
              update = old: builtins.map (pathToXml "Partition") old.${"Partition"};
            }
            {
              path = [ "Module" "Schedules" ];
              update = pathToXml "Schedules";
            }
          ]
            parsed-xml;
          # when converting xml -> json, one sub element becomes a sub
          # attribute while multiple sub elements with the same tag become a
          # list. We always want these to be a list, if in question one with
          # only a single element
          listsExpanded = pkgs.lib.updateManyAttrsByPath [
            {
              path = [ "Module" "Channels" "SamplingChannel" ];
              update = maybeListToList;
            }
            {
              path = [ "Module" "Channels" "QueuingChannel" ];
              update = maybeListToList;
            }
            {
              path = [ "Module" "Partitions" ];
              update = maybeListToList;
            }
            {
              path = [ "Schedules" "Schedule" ];
              update = maybeListToList;
            }
          ]
            merged;
          expanded-xml = listsExpanded;
        in
        expanded-xml;
      # lib.build-xcf = { pkgs, xng-ops, xng-config, src }: { };
      # lib.build-partition = { pkgs, xng-ops, xng-config, src, name }: { };
      # lib.build-sys-image = { pkgs, xng-ops, xng-config, partitions }: { };


      # compile one XNG configuration using a custom nix/bash based builder
      # partitions is a map of a partition name to an attrset containing the src
      lib.buildXngSysImage =
        { pkgs # base package set to operate on
        , xngOps # xng release, can be derived using buildXngOps
        , name # output name of this derivation
        , partitions
        , extraBinaryBlobs ? { } # hex address to blob path for extra blobs in the sysimage
        , xcf
        , lithOsOps ? null
        , hardFp ? false
        , stdenv ? (if hardFp then
            pkgs.pkgsCross.armhf-embedded.stdenv
          else pkgs.pkgsCross.arm-embedded.stdenv)
        }:
        let
          target = xngOps.meta.target;
          fp = if (pkgs.lib.hasAttr "fpu" stdenv.hostPlatform.gcc) then "hard" else "soft";
          baseUrl = "http://www.fentiss.com/";
          atLeastVersion1_4_7 = pkgs.lib.strings.versionAtLeast xngOps.version "1.4.7";
        in
        # either an lithOsOps is available, or no partition requires one.
        assert lithOsOps != null || pkgs.lib.lists.all ({ enableLithOs ? false, ... }: !enableLithOs) (pkgs.lib.attrValues partitions);
        assert fp == "soft" || fp == "hard";

        # extraBinaryBlobs must be an attribute set of (string or path)
        assert pkgs.lib.lists.all
          (path: let type = builtins.typeOf path; in type == "path" || type == "string")
          (pkgs.lib.attrValues extraBinaryBlobs);

        stdenv.mkDerivation {
          inherit name;
          dontUnpack = true;
          dontFixup = true;
          nativeBuildInputs = [ pkgs.file pkgs.xmlstarlet xngOps.bin ];
          buildInputs = [ xngOps.dev lithOsOps ];

          # We don't want nix to mess with compiler flags more than necessary
          hardeningDisable = [ "all" ];

          configurePhase = ''
            runHook preConfigure
                
            info(){
              # bold green
              local INFO_BEGIN_ESCAPE='\033[1;32m'
              local INFO_END_ESCAPE='\033[0m'
              echo -e "''${INFO_BEGIN_ESCAPE}$1''${INFO_END_ESCAPE}"
            }

            error(){
              # bold red
              local ERROR_BEGIN_ESCAPE='\033[1;31m'
              local ERROR_END_ESCAPE='\033[0m'
              echo -e "''${ERROR_BEGIN_ESCAPE}$1''${ERROR_END_ESCAPE}"
            }

            info "configuring xcf for ${name}"
            set -x
            xcparser.${target} ${xcf}/module.xml xcf.c
            { set +x; } 2>/dev/null

            runHook postConfigure
          '';

          buildPhase = ''
            runHook preBuild

            local xngVersion="${xngOps.version}"

            # fail on everything
            set -Eeuo pipefail

            info "building configuration image"
            set -x
            $CC $TARGET_CFLAGS -O2 -nostdlib -Wl,--entry=0x0 -Wl,-T${xngOps.dev}/lds/xcf.lds xcf.c \
                -o xcf.${target}.elf
            $OBJCOPY -O binary xcf.${target}.elf xcf.${target}.bin
            { set +x; } 2>/dev/null

            info "gathering information"
            if [ "version_at_least_1_4_7" = ${if atLeastVersion1_4_7 then "version_at_least_1_4_7" else "no"} ]
            then
              local ns="xcfXml"
              local hvNs="$ns"
              local moduleNs="$ns"
              local partitionNs="$ns"
              local hypervisor_entry_point=$(xmlstarlet tr --xinclude ${./.}/passthrough.xsl ${xcf}/module.xml | xml sel -N "n=${baseUrl}$moduleNs" -t \
                  -v '/n:Module/n:Hypervisor/@entryPoint')
            else
              local hypervisor_xml=$(xml sel -N 'n=${baseUrl}xngModuleXml' -t \
                  -v '/n:Module/n:Hypervisor/@hRef' ${xcf}/module.xml)
              local hypervisor_entry_point=$(xml sel -N 'n=${baseUrl}xngHypervisorXml' -t \
                  -v '/n:Hypervisor/@entryPoint' ${xcf}/$hypervisor_xml)
              local hvNs="xngHypervisorXml"
              local moduleNs="xngModuleXml"
              local partitionNs="xngPartitionXml"
            fi

            if [ -z "$hypervisor_entry_point" ]
            then
              printf "Failed to discover hypervisor entry point"
              exit 1
            else
              printf "Hypervisor entry point is $hypervisor_entry_point"
            fi

            local xcf_entry_point=0x200000

            local args=("-e" "$hypervisor_entry_point" \
                "${xngOps.dev}/lib/xng.${target}.bin@$hypervisor_entry_point")

            ${builtins.concatStringsSep "\n"
              (pkgs.lib.attrsets.mapAttrsToList (name: {
                # Path to partition source code
                src,
                # Link against LithOS
                enableLithOs ? false,
                # Link against XRE even if linking against LithOS
                forceXre ? false,
                # Path to LithOS control file
                ltcf ? null
              }: ''
                info "gathering information for partition ${name}"
                local partition_xml=$(xml sel -N "n=${baseUrl}$partitionNs" -t \
                    -if '/n:Partition/@name="${name}"' --inp-name $(find ${xcf} -name '*.xml'))

                # check partition xml file exits
                [ -f "$partition_xml" ] || {
                    error "unable to find xml for partition ${name}"
                    exit 127
                }

                local entry_point=$(xml sel -N "n=${baseUrl}$partitionNs" -t \
                    -v '/n:Partition/@entryPoint' $partition_xml)

                # check entry point is a positive number
                (( entry_point >= 0 )) || {
                    error "unable to extract partition entry point for partition ${name}"
                    exit 1
                }

                args+=("${name}.${target}.bin@$entry_point")

                info "building partition ${name}"
                local object_code=()
                local extra_ld_args=("-Ttext $entry_point")

                if file --brief ${src} | grep 'C source'
                then
                    local object_code+=("${name}.${target}.o")
                    set -x
                    $CC $TARGET_CFLAGS -c -o ''${object_code[-1]} ${src}
                    { set +x; } 2>/dev/null
                elif file --brief ${src} | grep 'ar archive'
                then
                    local object_code+=("${src}")
                    extra_ld_args+=("--require-defined ${if enableLithOs then "main" else "PartitionMain"}")
                fi

                ${ if enableLithOs then ''
                    [ -f "${ltcf}" ] || {
                        error "unable to find ltcf ${ltcf} for partition ${name}"
                        exit 127
                    }
                    local ltcf_out_file="${name}_ltcf.o"
                    set -x
                    $CC $TARGET_CFLAGS -isystem ${lithOsOps}/include --include ${ltcf} \
                        -c -o "$ltcf_out_file" ${lithOsOps}/lib/ltcf.c
                    { set +x; } 2>/dev/null

                    object_code+=("${lithOsOps}/lib/lte_kernel.o" "$ltcf_out_file")

                    extra_ld_args+=(
                        "-T${lithOsOps}/lds/lithos-xng-${target}.lds"
                        "--start-group"
                        ${if forceXre then "-lxre.${fp}fp.armv7a-vmsa-tz" else ""}
                        "-lxc.${fp}fp.armv7a-vmsa-tz"
                        "-lfw.${fp}fp.armv7a-vmsa-tz"
                        "--end-group"
                    )
                '' else ''
                    extra_ld_args+=(
                        "-T${xngOps.dev}/lds/xre.lds"
                        "--start-group"
                        "-lxre.${fp}fp.armv7a-vmsa-tz"
                        "-lxc.${fp}fp.armv7a-vmsa-tz"
                        "-lfw.${fp}fp.armv7a-vmsa-tz"
                        "--end-group"
                    )
                '' }

                set -x
                $LD -EL ''${object_code[@]} -o ${name}.${target}.elf ''${extra_ld_args[@]}
                $OBJCOPY -O binary ${name}.${target}.elf ${name}.${target}.bin
                { set +x; } 2>/dev/null

              '') partitions)}

            args+=(${pkgs.lib.escapeShellArgs (pkgs.lib.attrsets.mapAttrsToList (addr: src: "${src}@${addr}") extraBinaryBlobs)})

            args+=("xcf.${target}.bin@$xcf_entry_point" "sys_img.elf")

            info "building image"
            set -x
            elfbdr.py ''${args[@]}
            { set +x; } 2>/dev/null

            runHook postBuild
          '';

          installPhase = ''
            runHook preInstall

            mkdir $out
            mv *.{bin,c,elf} $out/
            runHook postInstall
          '';
        };

      templates = {
        xng-build = {
          path = ./template;
          description = "Simple build script for XNG examples";
        };
      };
      templates.default = self.templates.xng-build;

      ### checks against known fentISS releases
      checks.x86_64-linux =
        let
          pkgs = import nixpkgs {
            inherit system;
            config.permittedInsecurePackages = [
              "python-2.7.18.6"
              "python-2.7.18.6-env"
            ];
            # https://github.com/NixOS/nixpkgs/pull/42637
            overlays = [
              (final: prev: {
                requireFile = args: (prev.requireFile args).overrideAttrs (_: { allowSubstitutes = true; });
              })
            ];
          };
        in
        { }
        // (import ./checks/xng-1.4-smp.nix { inherit pkgs; xng-flake-utils = self; })
        // (import ./checks/xng-1.4.7-smp.nix { inherit pkgs; xng-flake-utils = self; })
        // (import ./checks/xng-1.3-monocore.nix { inherit pkgs; xng-flake-utils = self; })
        // (import ./checks/ske-2.1.0.nix { inherit pkgs; xng-flake-utils = self; });
    };
}
