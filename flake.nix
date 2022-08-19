{
  outputs = { self, nixpkgs }:
    let
      system = "x86_64-linux";
      pkgs = nixpkgs.legacyPackages."${system}";
      customPython = (pkgs.python.withPackages (pythonPackages: with pythonPackages; [ lxml ]));
    in
    rec {
      # build an XNG OPS from a tarball release
      lib.buildXngOps = { pkgs, src, name ? "xng-ops" }: pkgs.stdenv.mkDerivation {
        inherit name src;
        nativeBuildInputs = [ pkgs.autoPatchelfHook ];
        buildInputs = with pkgs; [
          (python3.withPackages (pythonPackages: with pythonPackages; [ lxml ]))
          libxml2
        ];
        installPhase = ''
          runHook preInstall
          mkdir $out
          cp -r . $out/
          runHook postInstall
        '';
      };

      # compile one XNG configuration
      lib.buildXngConfig = { pkgs, xngOps, name, src, xngConfigurationPath }: pkgs.stdenv.mkDerivation {
        inherit name src;
        nativeBuildInputs = [ pkgs.gcc-arm-embedded xngOps ];
        XNG_ROOT_PATH = xngOps;
        postPatch = ''
          for file in $( find -name Makefile -o -name '*.mk' ); do
            sed --in-place 's|^\(\s*XNG_ROOT_PATH\s*=\s*\).*$|\1${xngOps}|' "$file"
          done
          cd '${xngConfigurationPath}'
        '';
        dontFixup = true;
        installPhase = "mkdir $out; cp *.bin *.elf $out/";
      };
      lib.buildXngSysImage = { pkgs, xngOps, name, partitions, xcf, target, stdenv ? pkgs.stdenvNoCC }: stdenv.mkDerivation {
        inherit name;
        dontUnpack = true;
        dontFixup = true;
        nativeBuildInputs = [ xngOps pkgs.binutils pkgs.file pkgs.gcc-arm-embedded pkgs.xmlstarlet ];
        buildInputs = [ xngOps ];

        configurePhase = ''
          runHook preConfigure

          echo "configuring xcf for ${name}"
          xcparser.${target} ${xcf}/module.xml xcf.c

          runHook postConfigure
        '';

        buildPhase = ''
          runHook preConfigure
          set -x

          CC=arm-none-eabi-gcc
          LD=arm-none-eabi-ld
          OBJCOPY=arm-none-eabi-objcopy
          export TARGET_CFLAGS="-ffreestanding -mabi=aapcs -mlittle-endian \
            -march=armv7-a -mtune=cortex-a9 -mfpu=neon -DNEON -D${pkgs.lib.toUpper target} \
            -Wall -Wextra -pedantic -std=c99 -fno-builtin -O2 -fno-short-enums \
            -ffreestanding -I${xngOps}/include -I${xngOps}/include/xre-${target} \
            -I${xngOps}/lib/include -I${xngOps}/include/xc -mfloat-abi=soft \
            -mthumb"

          echo "building configuration image"
          $CC $TARGET_CFLAGS -O2 -nostdlib -Wl,--entry=0x0 \
            -Wl,-T${xngOps}/lds/xcf.lds \
            xcf.c -o xcf.${target}.elf
          $OBJCOPY -O binary xcf.${target}.elf xcf.${target}.bin

          echo "gathering information"
          local hypervisor_xml=$(xml sel -N 'n=http://www.fentiss.com/xngModuleXml' -t -v '/n:Module/n:Hypervisor/@hRef' ${xcf}/module.xml)
          local hypervisor_entry_point=$(xml sel -N 'n=http://www.fentiss.com/xngHypervisorXml' -t -v '/n:Hypervisor/@entryPoint' ${xcf}/$hypervisor_xml)
          local xcf_entry_point=0x200000

          echo "-e $hypervisor_entry_point ${xngOps}/lib/xng.${target}.bin@$hypervisor_entry_point" >> args
          ${builtins.concatStringsSep "\n"
            (pkgs.lib.attrsets.mapAttrsToList (name: src: ''
              echo "building partition ${name}"
              # TODO check what src is
              if file --brief ${src} | grep 'C source'
              then
                $CC $TARGET_CFLAGS -c -o ${name}.${target}.elf ${src}
              elif file --brief ${src} | grep 'ar archive'
              then
                $LD --relocatable --require-defined PartitionMain -nostdlib \
                -o ${name}.${target}.elf ${src}
              fi

              $OBJCOPY -O binary ${name}.${target}.elf ${name}.${target}.bin

              # find corresponding xml
              local partition_xml=$(xml sel -N 'n=http://www.fentiss.com/xngPartitionXml' -t -if '/n:Partition/@name="${name}"' --inp-name ${xcf}/*.xml)
              local entry_point=$(xml sel -N 'n=http://www.fentiss.com/xngPartitionXml' -t -v '/n:Partition/@entryPoint' ${xcf}/$partition_xml)
              echo "${name}.${target}.bin@$entry_point" >> args
            '') partitions)}

          echo "xcf.${target}.bin@$xcf_entry_point sys_img.elf" >> args

          echo "building image"
          TARGET_CC="$CC" elfbdr.py $(cat args | tr '\n' ' ')

          runHook postConfigure
        '';

        installPhase = ''
          mkdir $out
          mv args *.{bin,c,elf} $out/
        '';
      };
      
      templates = {
        xng-build = {
          path = ./template;
          description = "Simple build script for XNG examples";
        };
      };
      templates.default = self.templates.xng-build;

      # checks.x86_64-linux =
      #   let
      #     xngSrc = ./14-033.094.ops+armv7a-vmsa-tz+zynq7000.r16736;
      #     exampleDir = xngSrc + "/xre-examples";
      #     xngOps = lib.buildXngOps {
      #       inherit pkgs;
      #       src = ./14-033.094.ops+armv7a-vmsa-tz+zynq7000.r16736;
      #     };
      #     target = "armv7a-vmsa-tz";
      #   in
      #   {
      #     example-hello_world = lib.buildXngSysImage {
      #       inherit pkgs target xngOps;
      #       name = "hello_world";
      #       xcf = exampleDir + "/hello_world/xml";
      #       partitions.hello_world = exampleDir + "/hello_world/hello_world.c";
      #     };
      #     example-queuing_port = lib.buildXngSysImage {
      #       inherit pkgs target xngOps;
      #       name = "queuing_port";
      #       xcf = exampleDir + "/queuing_port/xml";
      #       partitions.src_partition = exampleDir + "/queuing_port/src0.c";
      #       partitions.dst_partition = exampleDir + "/queuing_port/dst0.c";
      #     };
      #     # example-reset_hypervisor = lib.buildXngSysImage {
      #     #   inherit name pkgs target xngOps;
      #     #   xcf = exampleDir + "/reset_hypervisor/xml";
      #     # };
      #     example-sampling_port = lib.buildXngSysImage {
      #       inherit pkgs target xngOps;
      #       name = "sampling_port";
      #       xcf = exampleDir + "/sampling_port/xml";
      #       partitions.src_partition = exampleDir + "/sampling_port/src0.c";
      #       partitions.dst_partition0 = exampleDir + "/sampling_port/dst0.c";
      #       partitions.dst_partition1 = exampleDir + "/sampling_port/dst1.c";
      #     };
      #     example-sampling_port_smp = lib.buildXngSysImage {
      #       inherit pkgs target xngOps;
      #       name = "sampling_port_smp";
      #       xcf = exampleDir + "/sampling_port_smp/xml";
      #       partitions.partition0 = exampleDir + "/sampling_port_smp/partition0.c";
      #       partitions.partition1 = exampleDir + "/sampling_port_smp/partition1.c";
      #     };
      #     example-system_timer = lib.buildXngSysImage {
      #       inherit pkgs target xngOps;
      #       name = "system_timer";
      #       xcf = exampleDir + "/system_timer/xml";
      #       partitions.partition = exampleDir + "/system_timer/system_timer.c";
      #     };
      #     example-vfp = lib.buildXngSysImage {
      #       inherit pkgs target xngOps;
      #       name = "vfp";
      #       xcf = exampleDir + "/vfp/xml";
      #       partitions.partition0 = exampleDir + "/vfp/vfp0.c";
      #       partitions.partition1 = exampleDir + "/vfp/vfp1.c";
      #     };
      #   };
    };
}

